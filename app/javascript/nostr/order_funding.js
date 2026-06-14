import { getEncodedToken } from "@cashu/cashu-ts"
import { ensureMintSupports, lockHtlc, lockP2PK2of3, topUpAmount, proofState } from "nostr/cashu_escrow"
import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"
import { idbGet, idbPut } from "nostr/escrow_store"

// The consumer's browser-side funding action (brief sec 9-10): mint the order budget on demand over
// Lightning, lock it as a NUT-14 HTLC to the provider with a timelock refund to the consumer, durably
// back up the unlock material, and produce the report Rails records. The runtime never sees the
// privkey/preimage/token (brief sec 6.3); Rails stores only observable data (Y values, hashlock,
// locktime, P2PK pubkeys).

const BACKUP_SUBJECT = "switchboard-escrow-backup"
const PAYOUT_SUBJECT = "switchboard-escrow-payout"
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
  wallet, mintUrl, amount, providerPubkey, consumerRefundPubkey, locktime, orderId, onInvoice, onStatus, signal, backup,
}) {
  // mintPaidProofs covers the order amount PLUS the mint's lock-swap fee (it sizes the mint to the actual proof
  // set), so the lock of exactly `amount` balances; the provider still receives the full order amount.
  const proofs = await mintPaidProofs(wallet, amount, { orderId, mintUrl, onInvoice, onStatus, signal })

  // Back up the pre-lock proofs (best-effort; backup never throws) so the minted ecash survives device loss in
  // the brief mint -> lock window, not just a same-browser reload.
  await backup?.(proofs)

  onStatus?.("locking")
  const lock = await lockHtlc({ wallet, amount, proofs, providerPubkey, consumerRefundPubkey, locktime })
  const lockedProofs = cleanProofs(lock.lockedProofs)
  const fields = {
    mint_url: mintUrl, hashlock: lock.hash, locktime: String(locktime),
    lock_pubkey: providerPubkey, refund_pubkey: consumerRefundPubkey,
  }
  await persistStage(orderId, { stage: "locked", token: lock.token, mint: mintUrl, locktime, proofs: lockedProofs, preimage: lock.preimage, fields })
  const payload = reportProofs(await proofState({ wallet, proofs: lockedProofs }), lockedProofs, fields)

  return { payload, token: lock.token, preimage: lock.preimage, lockedProofs }
}

// Tier-2 (2-of-3 arbiter) mint -> lock -> report. No hashlock; the payload carries the arbiter pubkey and
// n_sigs=2. arbiterPubkey is the PLATFORM key (advertised by Rails); Rails rejects any other arbiter.
export async function mintLockAndReportTier2({
  wallet, mintUrl, amount, consumerPubkey, providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime,
  orderId, onInvoice, onStatus, signal, backup,
}) {
  // mintPaidProofs covers the order amount PLUS the mint's lock-swap fee, so the lock of exactly `amount` balances.
  const proofs = await mintPaidProofs(wallet, amount, { orderId, mintUrl, onInvoice, onStatus, signal })

  // Back up the pre-lock proofs (best-effort) so the minted ecash survives device loss before the lock lands.
  await backup?.(proofs)

  onStatus?.("locking")
  const lock = await lockP2PK2of3({
    wallet, amount, proofs, consumerPubkey, providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime,
  })
  const lockedProofs = cleanProofs(lock.lockedProofs)
  const fields = {
    mint_url: mintUrl, locktime: String(locktime), lock_pubkey: providerPubkey,
    refund_pubkey: consumerRefundPubkey, arbiter_pubkey: arbiterPubkey, required_signatures: 2,
  }
  await persistStage(orderId, { stage: "locked", token: lock.token, mint: mintUrl, locktime, proofs: lockedProofs, fields })
  const payload = reportProofs(await proofState({ wallet, proofs: lockedProofs }), lockedProofs, fields)

  return { payload, token: lock.token, lockedProofs }
}

// Reduce a locked proof to the minimal spendable shape the backup + redeem + the NIP-17 cosign message need:
// drop the dleq (the mint's offline-verification proof, whose BigInts break JSON serialization and structured
// clone in ways that corrupt the amount) and coerce the amount to a plain number. The dleq is not needed to
// spend, so a swap with these proofs still redeems at the mint.
const cleanProofs = (proofs) => proofs.map((p) => ({ id: p.id, amount: Number(p.amount), secret: p.secret, C: p.C }))

// Persist the order's escrow record at its current stage (quote -> minted -> locked -> reported). Each write is
// the full record for the order; the resume logic (mintPaidProofs + the funding controller) reads the furthest
// stage reached, so a reload continues FORWARD without re-quoting or re-minting. Proofs are cleaned of the
// unserializable dleq before they are ever stored here.
async function persistStage(orderId, record) {
  if (orderId) await idbPut("escrow_secrets", orderId, { orderId, savedAt: Math.floor(Date.now() / 1000), ...record })
}

// Re-derive the report payload from a crash-saved marker whose proofs were locked but whose report never
// landed (a resume that finds `token` but no `payload`). The Y values come from a fresh proofState.
export async function reportFromSaved(wallet, saved) {
  return reportProofs(await proofState({ wallet, proofs: saved.proofs }), saved.proofs, saved.fields)
}

// Obtain `amount` sats of unspent proofs via the bolt11 flow as a FORWARD-ONLY, refresh-safe, RECOVERABLE state
// machine persisted per order. It never re-mints already-paid funds, never re-locks already-spent ones, and
// TOPS UP rather than abandons -- so an attempt that minted too little (e.g. it paid the order amount before the
// mint's lock-swap fee was accounted for) recovers by paying only the small difference, not the whole amount.
//   - enough already minted (a reload after a complete mint): return the saved proofs, never mint twice. First
//     verify they are still UNSPENT: a SPENT set means a prior lock swap consumed them (a crash after the swap),
//     which cannot be re-locked, so fail honestly.
//   - some minted but short (a top-up / recovery): keep the recovered proofs and mint only the shortfall.
//   - a quote already in flight (a reload before the mint): reuse the SAME invoice, never re-quote -- UNLESS it
//     expired unpaid (then re-issue; a paid quote is never dropped, so a payment is never orphaned).
//   - fresh: create the quote and persist it BEFORE the invoice is surfaced, so even a reload before payment resumes.
// onInvoice(bolt11, quoteId) (re)surfaces the invoice; onStatus(stage) drives the UI; signal cancels.
async function mintPaidProofs(wallet, amount, { orderId, mintUrl, onInvoice, onStatus, signal }) {
  await ensureMintSupports(wallet)

  const saved = orderId ? await loadSecrets(orderId) : null

  // Proofs a prior attempt already minted, RECOVERED rather than abandoned. Verify they are still UNSPENT: a
  // SPENT set means a prior lock swap consumed them and the unlock key was lost, which cannot be re-locked.
  const existing = saved?.mintedProofs ?? []
  if (existing.length) await assertMintedSpendable(wallet, existing)

  // What to mint NOW so the combined proofs cover `amount` + the mint's lock-swap fee. Sized from the actual
  // existing proof count, so a top-up onto an already-minted (non-optimal) set is correct on a fee mint.
  const owed = await topUpAmount(wallet, amount, existing)
  if (owed <= 0) return existing // existing already covers the lock + fee; never mint twice

  // Reuse a saved IN-FLIGHT quote (stage "quote": created, maybe paid, not yet minted) so a reload never issues
  // a duplicate invoice. After a "minted" stage the saved quote is consumed, so a top-up issues a fresh quote.
  const inFlight = saved?.stage === "quote"
  let quoteId = inFlight ? saved.quote : null
  let bolt11 = inFlight ? saved.request : null
  let expiry = inFlight ? (saved.expiry ?? null) : null
  if (quoteId && await quoteExpiredUnpaid(wallet, quoteId)) {
    quoteId = null // the saved invoice died unpaid; replace it rather than reuse a dead one
    bolt11 = null
    expiry = null
  }

  if (!quoteId) {
    onStatus?.("invoice")
    const quote = await withTimeout(wallet.createMintQuoteBolt11(owed), "the mint did not issue an invoice")
    quoteId = quote.quote
    bolt11 = quote.request
    expiry = quote.expiry ?? null
    // Persist the in-flight quote AND any recovered proofs BEFORE the invoice is shown, so a reload reuses THIS
    // invoice and keeps the recovered proofs.
    await persistStage(orderId, { stage: "quote", quote: quoteId, request: bolt11, expiry, amount, mint: mintUrl, mintedProofs: existing })
  }

  onInvoice?.(bolt11, quoteId) // (re)surface the invoice to pay
  await waitForPaid(wallet, quoteId, { expiry, onStatus, signal })

  onStatus?.("minting")
  const minted = await withTimeout(wallet.mintProofsBolt11(owed, quoteId), "the mint did not issue the ecash")
  const proofs = [ ...existing, ...cleanProofs(minted?.proofs ?? minted) ]
  // Persist the full minted set BEFORE locking: a reload between mint and lock resumes from here, never re-minting.
  await persistStage(orderId, { stage: "minted", amount, mint: mintUrl, mintedProofs: proofs })
  return proofs
}

// Resume guard for the narrow window where a lock swap SPENT the minted proofs but crashed before the 'locked'
// marker (and the token/preimage) was persisted: those funds are locked at the mint but the unlock material is
// gone, so a re-lock can only fail. Detect the SPENT state (NUT-07) and surface an honest, actionable error
// instead of silently retrying a swap on already-spent inputs forever. A mint we cannot reach is left to the
// lock attempt to surface -- we never block funding on a transient status check.
async function assertMintedSpendable(wallet, proofs) {
  let states
  try {
    states = await withTimeout(proofState({ wallet, proofs }), "the mint did not answer")
  } catch {
    return
  }

  if (states.some((s) => s.state === "SPENT")) {
    throw new Error("This order's funds were locked in an earlier attempt that did not finish recording, and the unlock key was lost in that crash. They cannot be re-locked; please contact support to recover this order.")
  }
}

// Has a saved quote expired WITHOUT being paid? Checked on resume so a dead invoice is replaced, not reused.
// NUT-04 has no EXPIRED state (verified against cashu-ts v4.5.1: MintQuoteState is UNPAID|PAID|ISSUED), so we
// judge by the quote's own expiry timestamp. PAID/ISSUED always wins -- a paid quote is never treated as dead,
// so a payment is never orphaned -- and a transient check failure is treated as still-live (safe: at worst we
// keep waiting and surface expiry via waitForPaid).
async function quoteExpiredUnpaid(wallet, quoteId) {
  try {
    const quote = await withTimeout(wallet.checkMintQuoteBolt11(quoteId), "the mint did not answer")
    if (quote.state === "PAID" || quote.state === "ISSUED") return false

    return isExpired(quote.expiry)
  } catch {
    return false
  }
}

// Attach the reportable proofs (Y + amount + keyset, never the spendable secret/C) to the lock-term fields.
function reportProofs(states, lockedProofs, fields) {
  const proofs = lockedProofs.map((proof, i) => ({ y: states[i].Y, amount: Number(proof.amount), keyset_id: proof.id }))

  return { ...fields, proofs }
}

// Poll the mint until the invoice is PAID (or already ISSUED on a re-entry); honor an AbortSignal. A transient
// poll failure (the mint rate-limiting our status checks, or a network blip) is NOT a funding failure -- the
// invoice may simply be unpaid yet -- so per-poll errors are swallowed and we keep polling. The wait ends on:
// the abort signal; a confirmed payment; the quote's own expiry passing (NUT-04 has no EXPIRED state, so we
// stop by timestamp rather than poll a dead invoice for the full budget); or the overall budget (~6 min at 3s,
// the fallback when the mint gave no expiry). Polling slower also stays under mint rate limits.
async function waitForPaid(wallet, quoteId, { expiry, onStatus, signal, intervalMs = 3000, tries = 120 } = {}) {
  for (let i = 0; i < tries; i++) {
    if (signal?.aborted) throw new Error("funding cancelled")

    let state
    try {
      const quote = await withTimeout(wallet.checkMintQuoteBolt11(quoteId), "the mint did not answer")
      state = quote.state
    } catch {
      // a rate-limited / slow status check is not a funding failure; keep polling
    }

    if (state === "PAID" || state === "ISSUED") return
    // Only declare the invoice expired when the mint actually answered (state is defined): a network outage
    // leaves state undefined, and must NOT be mistaken for expiry -- keep polling until it recovers or the budget ends.
    if (state !== undefined && isExpired(expiry)) throw new Error("The Lightning invoice expired before it was paid. Start funding again for a fresh invoice.")

    onStatus?.("waiting")
    await sleep(intervalMs)
  }

  throw new Error("invoice was not paid in time")
}

// A quote's expiry is unix-seconds (or null/absent if the mint set none). Absent/unparseable expiry => treated
// as not-expired, so the 6-min poll budget remains the only bound (graceful for mints that omit it).
const isExpired = (expiry) => Number.isFinite(expiry) && expiry > 0 && expiry <= Math.floor(Date.now() / 1000)

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

// The fast local copy of an order's unlock material, or null. Defensively re-clean any stored proofs: a record
// written by older code may still carry the unserializable dleq (BigInts), which would otherwise break the
// JSON.stringify in backupSecrets on a resume. cleanProofs is idempotent on already-clean proofs.
export async function loadSecrets(orderId) {
  return sanitizeRecord(await idbGet("escrow_secrets", orderId))
}

function sanitizeRecord(record) {
  if (!record) return null

  if (Array.isArray(record.proofs)) record.proofs = cleanProofs(record.proofs)
  if (Array.isArray(record.mintedProofs)) record.mintedProofs = cleanProofs(record.mintedProofs)

  return record
}

// --- the SETTLEMENT payout (the spendable proofs a redeem/refund produces) ---

// Capture a settled payout so the payee NEVER loses it: the settlement swap mints fresh ecash whose random
// secrets exist only in this proof set. Persist locally (mandatory -- the payee's primary claim material) and to
// an encrypted self-DM on relays (best-effort cross-device backup), and return a copyable Cashu token. `kind` is
// "released" (provider) or "refunded" (consumer). Uses its own idb store so it never clobbers the locked-order
// record. The relay copy is best-effort: the settlement swap already happened and the token is held locally +
// shown, so a relay outage must not fail an irreversible settlement.
export async function keepPayout({ signer, ownPubkey, relays, orderId, mint, proofs, kind }) {
  const clean = cleanProofs(proofs)
  const amount = clean.reduce((sum, proof) => sum + Number(proof.amount), 0)
  const record = { orderId, kind, mint, proofs: clean, amount, savedAt: Math.floor(Date.now() / 1000) }

  // Persist the raw proofs FIRST. They carry random, seedless secrets that exist only here, so they are the
  // irreplaceable claim material; every later step (token encoding, the relay backup) is best-effort and
  // re-derivable from this record, and so must never run before -- or be able to discard -- the proofs.
  await savePayout(record)

  // Encode a copyable token and re-persist it. Best-effort: the token is re-derivable from { mint, proofs } on
  // load, so an encode hiccup must not lose the already-saved proofs.
  try {
    record.token = encodePayoutToken(record)
    await savePayout(record)
  } catch {
    // proofs are saved; loadPayout re-derives the token from { mint, proofs }
  }

  await backupPayoutToRelay(record, { signer, ownPubkey, relays })

  return { token: record.token ?? null, amount }
}

// Encode a payout record's proofs as a copyable "cashuB..." token the payee can redeem at the mint anywhere.
function encodePayoutToken({ mint, proofs }) {
  return getEncodedToken({ mint, unit: "sat", proofs })
}

// Ensure a payout record carries a token, re-deriving it from { mint, proofs } when a prior encode did not
// persist one, so a saved/restored payout always surfaces a claimable token. Returns the record (or null).
function withDerivedToken(record) {
  if (!record) return null
  if (record.token || !record.mint || !Array.isArray(record.proofs)) return record

  try {
    record.token = encodePayoutToken(record)
  } catch {
    // leave the token absent; the proofs stay in the record for manual recovery
  }

  return record
}

// Best-effort persist of a payout to its own idb store. Never throws: a storage failure (quota, private mode)
// after an irreversible settlement must not abort -- the returned token + the relay backup remain claim paths.
async function savePayout(record) {
  try {
    await idbPut("escrow_payouts", record.orderId, record)
  } catch {
    // ignore; the surfaced token + the relay backup still carry the payout
  }
}

// Best-effort encrypted self-DM backup of a payout to relays (cross-device recovery). Never throws: the swap
// already happened and the token is held locally + shown, so a relay outage must not fail a settlement.
async function backupPayoutToRelay(record, { signer, ownPubkey, relays }) {
  try {
    const rumor = buildRumor({ authorPubkey: ownPubkey, content: JSON.stringify(record), recipients: [ ownPubkey ], subject: PAYOUT_SUBJECT })
    const { toSelf } = await wrapMessage(rumor, signer, ownPubkey)
    const set = new RelaySet(relays, { signer })

    try {
      await set.publishToMany(toSelf)
    } finally {
      set.close()
    }
  } catch {
    // the local copy + the surfaced token remain the payee's claim path
  }
}

// The payee's locally-saved payout for an order, or null (token re-derived if a prior encode did not save one).
export async function loadPayout(orderId) {
  return withDerivedToken(await idbGet("escrow_payouts", orderId))
}

// Disaster recovery: the payout from the encrypted self-DM backup on relays, or null.
export async function restorePayoutFromRelay({ signer, ownPubkey, relays, orderId }) {
  return withDerivedToken(await restoreFromRelay({ signer, ownPubkey, relays, orderId, subject: PAYOUT_SUBJECT }))
}

// Disaster recovery: the order's unlock material from the encrypted self-DM backup on relays, or null.
export function restoreSecretsFromRelay({ signer, ownPubkey, relays, orderId }) {
  return restoreFromRelay({ signer, ownPubkey, relays, orderId, subject: BACKUP_SUBJECT })
}

// Read a self-DM backup for `orderId` carrying `subject`, or null. The backup is a SELF-DM, so accept ONLY a
// wrap THIS signer's own key authored (unwrap authenticates rumor.pubkey as the verified seal signer, so an
// attacker cannot forge one as ownPubkey) carrying the expected subject. Anyone can gift-wrap a forged record
// p-tagged to ownPubkey; without the self-author + subject pin a losing party could plant bogus data and
// disable the winner's recovery.
async function restoreFromRelay({ signer, ownPubkey, relays, orderId, subject }) {
  const set = new RelaySet(relays, { signer })

  try {
    for (const wrap of await collectWraps(set, ownPubkey)) {
      try {
        const rumor = await unwrap(wrap, signer)
        if (rumor.pubkey !== ownPubkey) continue
        if (!rumor.tags.some(([ key, value ]) => key === "subject" && value === subject)) continue

        const record = JSON.parse(rumor.content)
        if (record.orderId === orderId) return record
      } catch {
        // skip a wrap this signer cannot read or that is not for this subject
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
