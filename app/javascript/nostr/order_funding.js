import { ensureMintSupports, lockHtlc, lockP2PK2of3, proofState } from "nostr/cashu_escrow"
import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"
import { idbGet, idbPut } from "nostr/escrow_store"

// The consumer's browser-side funding action (brief sec 9-10): mint the order budget on demand over
// Lightning, lock it as a NUT-14 HTLC to the provider with a timelock refund to the consumer, durably
// back up the unlock material, and produce the report Rails records. The runtime never sees the
// privkey/preimage/token (brief sec 6.3); Rails stores only observable data (Y values, hashlock,
// locktime, P2PK pubkeys).

const BACKUP_SUBJECT = "switchboard-escrow-backup"
const FETCH_TIMEOUT = 4000
const MINT_CALL_TIMEOUT = 20000

// Bound a single mint call so a hung/slow mint cannot block the funding flow indefinitely.
function withTimeout(promise, message, ms = MINT_CALL_TIMEOUT) {
  return Promise.race([ promise, sleep(ms).then(() => { throw new Error(message) }) ])
}

// Tier-1 (HTLC) mint -> lock -> report. Returns { payload, token, preimage, lockedProofs }; payload matches
// the Rails Orders::Funding contract (mint_url, hashlock, locktime, lock/refund pubkeys, proofs[{y,amount,
// keyset_id}]). onInvoice(bolt11, quoteId) surfaces the invoice to pay; onStatus(stage) drives the UI;
// signal cancels.
export async function mintLockAndReport({
  wallet, mintUrl, amount, providerPubkey, consumerRefundPubkey, locktime, orderId, onInvoice, onStatus, signal,
}) {
  const proofs = await mintPaidProofs(wallet, amount, { onInvoice, onStatus, signal })

  onStatus?.("locking")
  const lock = await lockHtlc({ wallet, amount, proofs, providerPubkey, consumerRefundPubkey, locktime })
  const lockedProofs = cleanProofs(lock.lockedProofs)
  const fields = {
    mint_url: mintUrl, hashlock: lock.hash, locktime: String(locktime),
    lock_pubkey: providerPubkey, refund_pubkey: consumerRefundPubkey,
  }
  await persistLockedMarker(orderId, { token: lock.token, mint: mintUrl, locktime, proofs: lockedProofs, preimage: lock.preimage, fields })
  const payload = reportProofs(await proofState({ wallet, proofs: lockedProofs }), lockedProofs, fields)

  return { payload, token: lock.token, preimage: lock.preimage, lockedProofs }
}

// Tier-2 (2-of-3 arbiter) mint -> lock -> report. No hashlock; the payload carries the arbiter pubkey and
// n_sigs=2. arbiterPubkey is the PLATFORM key (advertised by Rails); Rails rejects any other arbiter.
export async function mintLockAndReportTier2({
  wallet, mintUrl, amount, consumerPubkey, providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime,
  orderId, onInvoice, onStatus, signal,
}) {
  const proofs = await mintPaidProofs(wallet, amount, { onInvoice, onStatus, signal })

  onStatus?.("locking")
  const lock = await lockP2PK2of3({
    wallet, amount, proofs, consumerPubkey, providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime,
  })
  const lockedProofs = cleanProofs(lock.lockedProofs)
  const fields = {
    mint_url: mintUrl, locktime: String(locktime), lock_pubkey: providerPubkey,
    refund_pubkey: consumerRefundPubkey, arbiter_pubkey: arbiterPubkey, required_signatures: 2,
  }
  await persistLockedMarker(orderId, { token: lock.token, mint: mintUrl, locktime, proofs: lockedProofs, fields })
  const payload = reportProofs(await proofState({ wallet, proofs: lockedProofs }), lockedProofs, fields)

  return { payload, token: lock.token, lockedProofs }
}

// Reduce a locked proof to the minimal spendable shape the backup + redeem + the NIP-17 cosign message need:
// drop the dleq (the mint's offline-verification proof, whose BigInts break JSON serialization and structured
// clone in ways that corrupt the amount) and coerce the amount to a plain number. The dleq is not needed to
// spend, so a swap with these proofs still redeems at the mint.
const cleanProofs = (proofs) => proofs.map((p) => ({ id: p.id, amount: Number(p.amount), secret: p.secret, C: p.C }))

// Crash-safety: persist a LOCAL marker the instant funds lock -- BEFORE the report round-trip below -- so a
// crash there cannot orphan the lock. The resume guard keys on `token` (never re-mints) and re-derives the
// report from `proofs` + `fields` (reportFromSaved). The full backup (with payload) overwrites this shortly.
async function persistLockedMarker(orderId, record) {
  if (orderId) await idbPut("escrow_secrets", orderId, { orderId, savedAt: Math.floor(Date.now() / 1000), ...record })
}

// Re-derive the report payload from a crash-saved marker whose proofs were locked but whose report never
// landed (a resume that finds `token` but no `payload`). The Y values come from a fresh proofState.
export async function reportFromSaved(wallet, saved) {
  return reportProofs(await proofState({ wallet, proofs: saved.proofs }), saved.proofs, saved.fields)
}

// Mint `amount` sats via the bolt11 flow: assert the mint, surface the invoice, wait for payment, return proofs.
async function mintPaidProofs(wallet, amount, { onInvoice, onStatus, signal }) {
  await ensureMintSupports(wallet)

  onStatus?.("invoice")
  const quote = await withTimeout(wallet.createMintQuoteBolt11(amount), "the mint did not issue an invoice")
  onInvoice?.(quote.request, quote.quote) // bolt11 to pay + the quote id
  await waitForPaid(wallet, quote.quote, { onStatus, signal })

  onStatus?.("minting")
  const minted = await withTimeout(wallet.mintProofsBolt11(amount, quote.quote), "the mint did not issue the ecash")
  return minted?.proofs ?? minted
}

// Attach the reportable proofs (Y + amount + keyset, never the spendable secret/C) to the lock-term fields.
function reportProofs(states, lockedProofs, fields) {
  const proofs = lockedProofs.map((proof, i) => ({ y: states[i].Y, amount: Number(proof.amount), keyset_id: proof.id }))

  return { ...fields, proofs }
}

// Poll the mint until the invoice is PAID (or already ISSUED on a re-entry); honor an AbortSignal.
async function waitForPaid(wallet, quoteId, { onStatus, signal, intervalMs = 2000, tries = 150 } = {}) {
  for (let i = 0; i < tries; i++) {
    if (signal?.aborted) throw new Error("funding cancelled")

    const { state } = await withTimeout(wallet.checkMintQuoteBolt11(quoteId), "the mint did not answer")
    if (state === "PAID" || state === "ISSUED") return

    onStatus?.("waiting")
    await sleep(intervalMs)
  }

  throw new Error("invoice was not paid in time")
}

// --- durable backup of the unlock material (local + encrypted self-DM) ---

// The consumer MUST keep {token, preimage} to release or refund: the Y values in Rails cannot rebuild a
// spendable token. Persist locally (fast) AND to a NIP-44-self-encrypted NIP-17 wrap on relays (survives
// device loss). Throws unless the relay copy lands, so a funded order is never left unrecoverable.
export async function backupSecrets({ signer, ownPubkey, relays, orderId, secrets }) {
  const record = { orderId, ...secrets, savedAt: Math.floor(Date.now() / 1000) }
  await idbPut("escrow_secrets", orderId, record)

  const rumor = buildRumor({ authorPubkey: ownPubkey, content: JSON.stringify(record), recipients: [ ownPubkey ], subject: BACKUP_SUBJECT })
  const { toSelf } = await wrapMessage(rumor, signer, ownPubkey)
  const set = new RelaySet(relays, { signer })

  try {
    const results = await set.publishToMany(toSelf)
    // ok = acked; timeout = open + sent but slow to ack (possibly stored). Only hard errors everywhere fail.
    if (!results.some((r) => r.status === "ok" || r.status === "timeout")) throw new Error("escrow backup did not reach any relay")
  } finally {
    set.close()
  }

  return record
}

// The fast local copy of an order's unlock material, or null.
export function loadSecrets(orderId) {
  return idbGet("escrow_secrets", orderId)
}

// Disaster recovery: the order's unlock material from the encrypted self-DM backup on relays, or null.
// The backup is a SELF-DM, so accept ONLY a wrap THIS signer's own key authored (unwrap authenticates
// rumor.pubkey as the verified seal signer, so an attacker cannot forge one as ownPubkey) carrying the
// backup subject. Anyone can gift-wrap a forged {orderId, proofs} p-tagged to ownPubkey; without the
// self-author + subject pin a losing party could plant bogus proofs and disable the winner's recovery.
export async function restoreSecretsFromRelay({ signer, ownPubkey, relays, orderId }) {
  const set = new RelaySet(relays, { signer })

  try {
    for (const wrap of await collectWraps(set, ownPubkey)) {
      try {
        const rumor = await unwrap(wrap, signer)
        if (rumor.pubkey !== ownPubkey) continue
        if (!rumor.tags.some(([ key, value ]) => key === "subject" && value === BACKUP_SUBJECT)) continue

        const record = JSON.parse(rumor.content)
        if (record.orderId === orderId) return record
      } catch {
        // skip a wrap this signer cannot read or that is not an escrow backup
      }
    }

    return null
  } finally {
    set.close()
  }
}

function collectWraps(set, ownPubkey) {
  return new Promise((resolve) => {
    const wraps = []
    const sub = set.subscribeMany([ { kinds: [ Kind.GIFT_WRAP ], "#p": [ ownPubkey ] } ], {
      onevent: (event) => wraps.push(event),
      oneose: () => { sub.close(); resolve(wraps) },
    })

    setTimeout(() => { sub.close(); resolve(wraps) }, FETCH_TIMEOUT)
  })
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
