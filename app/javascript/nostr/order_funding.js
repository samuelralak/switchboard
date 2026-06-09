import { ensureMintSupports, lockHtlc, proofState } from "nostr/cashu_escrow"
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

// Mint -> lock -> report. Returns { payload, token, preimage, lockedProofs }; payload matches the Rails
// Orders::Funding contract (mint_url, hashlock, locktime, lock/refund pubkeys, proofs[{y,amount,keyset_id}]).
// onInvoice(bolt11, quoteId) surfaces the invoice to pay; onStatus(stage) drives the UI; signal cancels.
export async function mintLockAndReport({
  wallet, mintUrl, amount, providerPubkey, consumerRefundPubkey, locktime, onInvoice, onStatus, signal,
}) {
  await ensureMintSupports(wallet)

  onStatus?.("invoice")
  const quote = await withTimeout(wallet.createMintQuoteBolt11(amount), "the mint did not issue an invoice")
  onInvoice?.(quote.request, quote.quote) // bolt11 to pay + the quote id
  await waitForPaid(wallet, quote.quote, { onStatus, signal })

  onStatus?.("minting")
  const minted = await withTimeout(wallet.mintProofsBolt11(amount, quote.quote), "the mint did not issue the ecash")
  const proofs = minted?.proofs ?? minted

  onStatus?.("locking")
  const lock = await lockHtlc({ wallet, amount, proofs, providerPubkey, consumerRefundPubkey, locktime })
  const payload = await reportPayload({ wallet, lock, mintUrl, locktime, providerPubkey, consumerRefundPubkey })

  return { payload, token: lock.token, preimage: lock.preimage, lockedProofs: lock.lockedProofs }
}

// Only observable data: the proof Y values (one-way from the secret), hashlock, locktime, P2PK pubkeys.
async function reportPayload({ wallet, lock, mintUrl, locktime, providerPubkey, consumerRefundPubkey }) {
  const states = await proofState({ wallet, proofs: lock.lockedProofs })
  const proofs = lock.lockedProofs.map((proof, i) => ({ y: states[i].Y, amount: Number(proof.amount), keyset_id: proof.id }))

  return {
    mint_url: mintUrl, hashlock: lock.hash, locktime: String(locktime),
    lock_pubkey: providerPubkey, refund_pubkey: consumerRefundPubkey, proofs,
  }
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
export async function restoreSecretsFromRelay({ signer, ownPubkey, relays, orderId }) {
  const set = new RelaySet(relays, { signer })

  try {
    for (const wrap of await collectWraps(set, ownPubkey)) {
      try {
        const record = JSON.parse((await unwrap(wrap, signer)).content)
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
