import { createRandomSecretKey, getPubKeyFromPrivKey } from "@cashu/cashu-ts"
import { RelaySet } from "nostr/relay_set"
import { idbGet, idbPut } from "nostr/escrow_store"

// Per-account Cashu escrow identity (brief sec 9-10; NIP-60 + NIP-61). Each account holds ONE
// secp256k1 P2PK key, SEPARATE from its Nostr key, because NIP-07/bunker signers cannot raw-schnorr
// sign a Cashu proof secret. The private key is cached locally (IndexedDB) and durably backed up as a
// NIP-60 kind:17375 wallet event (NIP-44 encrypted to self, recoverable from any relay); the public
// key is advertised as a NIP-61 kind:10019 event so a counterparty can lock to it. The Rails runtime
// never sees the private key (brief sec 6.3).

const WALLET = 17375      // NIP-60 encrypted wallet event (replaceable)
const NUTZAP_INFO = 10019 // NIP-61 informational event (replaceable)
const FETCH_TIMEOUT = 4000

const nowSeconds = () => Math.floor(Date.now() / 1000)
const HEX64 = /^[0-9a-f]{64}$/         // a privkey
const P2PK = /^0[23][0-9a-f]{64}$/     // a SEC1-compressed pubkey

const toHex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
function fromHex(hex) {
  const out = new Uint8Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return out
}

// --- key material ---

// A fresh escrow keypair: privkey 64-hex, pubkey 66-hex SEC1-compressed (02/03 prefix). The pubkey is
// advertised AND passed to lockHtlc verbatim; never hand-prefix or truncate it to x-only.
export function newEscrowKey() {
  const sk = createRandomSecretKey()
  return { privkeyHex: toHex(sk), pubkeyHex: toHex(getPubKeyFromPrivKey(sk)) }
}

// Derive (and thereby validate) the pubkey for a stored privkey; throws on a malformed key.
export function pubkeyForPrivkey(privkeyHex) {
  if (typeof privkeyHex !== "string" || !HEX64.test(privkeyHex)) throw new Error("escrow privkey must be 64-hex")
  return toHex(getPubKeyFromPrivKey(fromHex(privkeyHex)))
}

// --- NIP-61 kind:10019 advertisement (public) ---

export function buildInfoEvent({ pubkeyHex, mints = [], relays = [], createdAt = nowSeconds() }) {
  const tags = [
    ["pubkey", pubkeyHex],
    ...mints.map((url) => ["mint", url, "sat"]),
    ...relays.map((url) => ["relay", url]),
  ]
  return { kind: NUTZAP_INFO, created_at: createdAt, content: "", tags }
}

// A counterparty's advertised escrow pubkey + accepted mints from their kind:10019, or null.
export function parseInfoEvent(event) {
  if (!event || event.kind !== NUTZAP_INFO || !Array.isArray(event.tags)) return null
  const pubkey = tagValue(event.tags, "pubkey")
  if (!pubkey || !P2PK.test(pubkey)) return null // a consumer locks funds to this; never trust a stray value
  return {
    pubkey,
    mints: tagValues(event.tags, "mint"),
    relays: tagValues(event.tags, "relay"),
  }
}

// --- NIP-60 kind:17375 durable backup (encrypted to self) ---

// The plaintext backed up: the escrow privkey + the mints it funds on, as a NIP-60 tag array.
function walletPayload({ privkeyHex, mints = [] }) {
  return JSON.stringify([["privkey", privkeyHex], ...mints.map((url) => ["mint", url])])
}

export async function buildWalletEvent(signer, accountPubkey, { privkeyHex, mints = [], createdAt = nowSeconds() }) {
  const content = await signer.nip44Encrypt(accountPubkey, walletPayload({ privkeyHex, mints }))
  return { kind: WALLET, created_at: createdAt, content, tags: [] }
}

// Decrypt + parse a kind:17375 the account signed for itself; returns { privkeyHex, mints } or null
// (wrong author, undecryptable for this signer, or malformed payload).
export async function parseWalletEvent(signer, accountPubkey, event) {
  if (!event || event.kind !== WALLET || event.pubkey !== accountPubkey) return null
  let rows
  try {
    rows = JSON.parse(await signer.nip44Decrypt(accountPubkey, event.content))
  } catch {
    return null
  }
  if (!Array.isArray(rows)) return null
  const privkeyHex = rows.find((r) => r[0] === "privkey")?.[1]
  if (!privkeyHex || !HEX64.test(privkeyHex)) return null // discard a malformed backup so the caller regenerates
  return { privkeyHex, mints: rows.filter((r) => r[0] === "mint" && r[1]).map((r) => r[1]) }
}

// --- per-account local cache (IndexedDB) ---

export const cachePut = (accountPubkey, privkeyHex) => idbPut("escrow_keys", accountPubkey, privkeyHex)
export const cacheGet = (accountPubkey) => idbGet("escrow_keys", accountPubkey)

// --- relay I/O + orchestration ---

// Newest signed event of `kind` by `author` on these relays, or null. The author is re-checked
// client-side: not every relay enforces the authors filter, and a relay's say-so is never trusted.
function fetchLatest(set, { kind, author }) {
  return new Promise((resolve) => {
    let latest = null
    const sub = set.subscribeMany([{ kinds: [kind], authors: [author] }], {
      onevent: (e) => {
        if (e.pubkey !== author) return
        if (!latest || (Number(e.created_at) || 0) > (Number(latest.created_at) || 0)) latest = e
      },
      oneose: () => { sub.close(); resolve(latest) },
    })
    setTimeout(() => { sub.close(); resolve(latest) }, FETCH_TIMEOUT)
  })
}

// Discover a counterparty's escrow pubkey + accepted mints (their kind:10019), or null.
export async function discover(counterpartyPubkey, relays) {
  const set = new RelaySet(relays)
  try {
    return parseInfoEvent(await fetchLatest(set, { kind: NUTZAP_INFO, author: counterpartyPubkey }))
  } finally {
    set.close()
  }
}

// Recover the escrow privkey from the account's own kind:17375 backup, or null (none published).
export async function restoreFromWallet(accountPubkey, signer, relays) {
  const set = new RelaySet(relays, { signer })
  try {
    return await parseWalletEvent(signer, accountPubkey, await fetchLatest(set, { kind: WALLET, author: accountPubkey }))
  } finally {
    set.close()
  }
}

// Publish a signed event to the relays, throwing unless it was ACKed by at least one (a generated key
// with no durable backup, or an unadvertised pubkey, must not be silently relied on). This gates funding
// BEFORE any mint, so unlike the post-mint message paths it requires a real OK (not a mere timeout):
// failing early here is safe, and proceeding on an uncertain escrow-key advertisement is not.
async function broadcast(set, event, what) {
  const results = await set.publishToMany(event)
  if (!results.some((r) => r.status === "ok")) throw new Error(`escrow ${what} did not reach any relay`)
}

// Re-publish the public advertisement (kind:10019); idempotent, replaceable.
export async function publishAdvertisement(signer, { pubkeyHex, mints = [], relays }) {
  const set = new RelaySet(relays, { signer })
  try {
    await broadcast(set, await signer.signEvent(buildInfoEvent({ pubkeyHex, mints, relays })), "advertisement")
  } finally {
    set.close()
  }
}

// Load-or-create the account's escrow identity: local cache -> relay backup -> generate. On generate,
// publish the encrypted backup (kind:17375) THEN the advertisement (kind:10019), then cache. Caching
// only after a successful backup means a cached key is always durably recoverable. Returns
// { privkeyHex, pubkeyHex }; the caller passes pubkeyHex to lockHtlc / advertises it.
//
// Serialized per account so two concurrent callers cannot each generate a different key and diverge the
// advertised kind:10019 from the backed-up kind:17375. navigator.locks serializes across same-origin
// tabs; the in-flight map is the fallback. This does NOT cover two distinct devices racing a first-ever
// setup before either backup propagates -- that needs relay-authoritative reconciliation (deferred).
const inflight = new Map()

export function ensureEscrowIdentity(opts) {
  const name = `escrow-identity:${opts.accountPubkey}`
  if (globalThis.navigator?.locks?.request) return navigator.locks.request(name, () => runEnsure(opts))
  if (inflight.has(name)) return inflight.get(name)
  const pending = Promise.resolve().then(() => runEnsure(opts)).finally(() => inflight.delete(name))
  inflight.set(name, pending)
  return pending
}

async function runEnsure({ accountPubkey, signer, relays, mints = [] }) {
  const cached = await cacheGet(accountPubkey)
  const fromCache = cached && asIdentity(cached)
  if (fromCache) return fromCache

  const restored = await restoreFromWallet(accountPubkey, signer, relays)
  if (restored) {
    await cachePut(accountPubkey, restored.privkeyHex)
    return { privkeyHex: restored.privkeyHex, pubkeyHex: pubkeyForPrivkey(restored.privkeyHex) }
  }

  const key = newEscrowKey()
  const set = new RelaySet(relays, { signer })
  try {
    await broadcast(set, await signer.signEvent(await buildWalletEvent(signer, accountPubkey, { ...key, mints })), "key backup")
    await broadcast(set, await signer.signEvent(buildInfoEvent({ pubkeyHex: key.pubkeyHex, mints, relays })), "advertisement")
  } finally {
    set.close()
  }
  await cachePut(accountPubkey, key.privkeyHex)
  return key
}

// A cached privkey -> identity, or null if the cached value is malformed (discard a poisoned cache and
// re-derive rather than throw on every load).
function asIdentity(privkeyHex) {
  try {
    return { privkeyHex, pubkeyHex: pubkeyForPrivkey(privkeyHex) }
  } catch {
    return null
  }
}

function tagValue(tags, name) {
  const found = tags.find((t) => t[0] === name && t[1])
  return found ? found[1] : null
}

function tagValues(tags, name) {
  return tags.filter((t) => t[0] === name && t[1]).map((t) => t[1])
}
