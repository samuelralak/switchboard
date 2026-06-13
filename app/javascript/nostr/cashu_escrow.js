import {
  OutputData, P2PKBuilder, getEncodedToken,
  signP2PKProof, createHTLCHash, isHTLCSpendAuthorised,
} from "@cashu/cashu-ts"

// Non-custodial manual-order escrow on Cashu (brief sections 9-10), browser-side: the consumer locks a
// NUT-14 HTLC token to the provider with a timelock refund to themselves; the runtime never holds the
// token or any key. Tier 1 (default): a plain HTLC whose release is consumer-gated (the provider can only
// redeem once the consumer reveals the preimage on delivery); after the locktime the consumer reclaims
// with a signature only. The lock builder keeps pubkeys/n_sigs/refund/locktime first-class so the Tier-2
// P2PK 2-of-3 arbiter drops in later with no wire change. API verified against @cashu/cashu-ts v4.5.1.
//
// CRITICAL: cashu-ts has no preimage-attach in its high-level receive, so the redeem witness is hand-built
// ({ preimage, signatures }) and submitted via a low-level mint swap. Do NOT route the redeem through
// wallet.receive (it cannot carry a preimage and would strand the provider's funds).

const SAT = "sat"

// Assert the mint advertises the spending conditions we depend on, FAIL-CLOSED before any value is locked.
// Reads the raw NUT-06 /v1/info nuts map (entries are { supported: bool }) directly, rather than depend on
// the MintInfo wrapper's accessor shape.
export async function ensureMintSupports(wallet) {
  await wallet.loadMint() // populate keysets used by later swaps
  const info = await (await fetch(`${wallet.mint.mintUrl}/v1/info`)).json()
  const nuts = info?.nuts ?? {}

  for (const nut of [ 7, 10, 11, 14 ]) {
    const entry = nuts[nut] ?? nuts[String(nut)]
    const ok = entry === true || entry?.supported === true
    if (!ok) throw new Error(`Mint ${wallet.mint.mintUrl} does not support NUT-${nut}`)
  }

  return wallet
}

// Lock `amount` sats to the provider as an HTLC: secret data = sha256(preimage), pubkeys = [provider],
// locktime, refund = [consumer]. Returns the encoded token (handed to the provider over the order thread)
// plus the preimage (the consumer's release secret, kept private until delivery is approved). pubkeys and
// refundKeys accept arrays + requiredSignatures/requiredRefundSignatures for a future Tier-2 2-of-3.
export async function lockHtlc({
  wallet, amount, proofs, providerPubkey, consumerRefundPubkey, locktime, preimage,
  requiredSignatures = 1, requiredRefundSignatures = 1,
}) {
  assertFutureLocktime(locktime)
  const { hash, preimage: pre } = createHTLCHash(preimage) // preimage is 32 bytes / 64 hex; throws otherwise

  const builder = new P2PKBuilder()
    .addLockPubkey(providerPubkey)         // before locktime: provider must sign (with the preimage)
    .addRefundPubkey(consumerRefundPubkey) // after locktime: consumer can sign alone (no preimage)
    .lockUntil(locktime)                   // unix-seconds; refund keys REQUIRE a locktime (builder enforces)
    .addHashlock(hash)                     // the HASH, never the preimage; flips the secret kind to HTLC
  if (requiredSignatures > 1) builder.requireLockSignatures(requiredSignatures)
  if (requiredRefundSignatures > 1) builder.requireRefundSignatures(requiredRefundSignatures)

  const options = builder.toOptions() // throws on no lock key / refund-without-locktime / >10 keys / oversize secret
  const { keep, send } = await wallet.send(amount, proofs, undefined, { send: { type: "p2pk", options } })
  const token = getEncodedToken({ mint: wallet.mint.mintUrl, unit: SAT, proofs: send })

  return { token, lockedProofs: send, change: keep, hash, preimage: pre, locktime }
}

// Provider redeems on release (the consumer has revealed the preimage). Hand-builds the { preimage,
// signatures } witness per proof, verifies it locally (needs BOTH preimage and a valid signature), then
// swaps the inputs into fresh provider-only proofs at the mint.
export async function redeemWithPreimage({ wallet, lockedProofs, preimage, providerPrivkey }) {
  const inputs = lockedProofs.map((proof) => {
    const signed = signP2PKProof({ ...proof, witness: JSON.stringify({ preimage }) }, providerPrivkey)
    if (!isHTLCSpendAuthorised(signed)) {
      throw new Error("HTLC witness not spend-authorised (wrong preimage or signature)")
    }

    // The raw mint swap requires the witness as a JSON string, not an object.
    return { ...signed, witness: typeof signed.witness === "string" ? signed.witness : JSON.stringify(signed.witness) }
  })

  return swapInputs(wallet, inputs)
}

// Consumer reclaims after the locktime with a signature only (no preimage). The refund key only becomes a
// valid witness once the (mint) clock has passed the locktime; before that the swap is rejected.
export async function refund({ wallet, token, consumerRefundPrivkey }) {
  return { proofs: await wallet.receive(token, { privkey: consumerRefundPrivkey }) }
}

// --- Tier 2: arbiter-mediated 2-of-3 P2PK (NO hashlock) -------------------------------------------------
// Lock `amount` to a NUT-11 P2PK 2-of-3 over {consumer, provider, arbiter}: the consumer key is the secret
// `data` (one of the signers), the provider + arbiter keys are the `pubkeys` tag, n_sigs = 2, and the refund
// pathway is the consumer alone after the locktime. Any two of the three release pre-locktime (happy =
// consumer+provider; dispute = arbiter+either); the arbiter is 1-of-3 so never sufficient alone, and is not
// in the refund set. No preimage: the delivery gate is the arbiter, not a hashlock. See
// docs/tier2-arbiter-escrow.md. The first addLockPubkey becomes `data`; the spike asserts the built shape.
export async function lockP2PK2of3({
  wallet, amount, proofs, consumerPubkey, providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime,
}) {
  assertFutureLocktime(locktime)

  const builder = new P2PKBuilder()
    .addLockPubkey(consumerPubkey)         // first lock key => secret.data, a signer in the 2-of-3
    .addLockPubkey(providerPubkey)         // => pubkeys tag
    .addLockPubkey(arbiterPubkey)          // => pubkeys tag
    .requireLockSignatures(2)              // any 2 of {consumer, provider, arbiter} before locktime
    .addRefundPubkey(consumerRefundPubkey) // consumer alone, after locktime (n_sigs_refund defaults to 1)
    .lockUntil(locktime)                   // refund keys REQUIRE a locktime (builder enforces)

  const options = builder.toOptions() // throws on no lock key / refund-without-locktime / >10 keys / oversize
  const { keep, send } = await wallet.send(amount, proofs, undefined, { send: { type: "p2pk", options } })
  const token = getEncodedToken({ mint: wallet.mint.mintUrl, unit: SAT, proofs: send })

  return { token, lockedProofs: send, change: keep, locktime }
}

// Append ONE key holder's signature to each proof's witness. The 2-of-3 release gathers these across two
// holders (a party's browser + the platform arbiter); chain it once per signer, then redeem2of3 submits.
export function coSignProofs(proofs, privkey) {
  return proofs.map((proof) => signP2PKProof(proof, privkey))
}

// Submit proofs that already carry >= n_sigs signatures as a low-level swap into fresh proofs. The mint
// verifies the multisig threshold; a short witness (1 of the 2-of-3, or a pre-locktime refund) is rejected.
export async function redeem2of3({ wallet, signedProofs }) {
  const inputs = signedProofs.map((proof) => ({
    ...proof, witness: typeof proof.witness === "string" ? proof.witness : JSON.stringify(proof.witness),
  }))

  return swapInputs(wallet, inputs)
}

// NUT-07 proof states + the witness on a spent proof: the runtime's authoritative settlement signal. A
// SPENT HTLC proof's witness reveals the preimage (= the release path was taken). Returns the raw states.
export async function proofState({ wallet, proofs }) {
  return wallet.checkProofsStates(proofs)
}

// Parse a NUT-07 witness string into { preimage, signatures }. The witness JSON shape is stable per NUT-14,
// so we parse it directly rather than depend on a helper's exact input type.
export function parseWitness(witness) {
  if (!witness) return { preimage: null, signatures: [] }

  try {
    const w = typeof witness === "string" ? JSON.parse(witness) : witness
    return { preimage: w?.preimage ?? null, signatures: w?.signatures ?? [] }
  } catch {
    return { preimage: null, signatures: [] }
  }
}

// --- internals ---

// Swap already-witnessed inputs into fresh proofs, accounting for the mint's NUT-02 input fee. The mint
// requires sum(inputs) == sum(outputs) + fee, so the outputs must total inputs - fee or it rejects the swap
// and the locked funds strand; getFeesForProofs is 0 on a fee-free mint (outputs == inputs, unchanged) and
// ~1 sat on a fee-charging one (the redeemer absorbs it). The outputs MUST use the inputs' own keyset, not the
// wallet's active one: a mint that rotated keysets between funding and redeem would otherwise mismatch inputs
// (keyset A) against outputs (keyset B) and the swap is rejected.
async function swapInputs(wallet, inputs) {
  const keyset = wallet.getKeyset(inputs[0]?.id)
  const inputTotal = inputs.reduce((sum, p) => sum + Number(p.amount), 0)
  const fee = wallet.getFeesForProofs(inputs)
  if (fee >= inputTotal) throw new Error(`mint input fee ${fee} >= locked amount ${inputTotal}; cannot redeem`)

  const outputs = OutputData.createRandomData(inputTotal - fee, keyset)
  const { signatures } = await wallet.mint.swap({ inputs, outputs: outputs.map((o) => o.blindedMessage) })

  return { proofs: outputs.map((o, i) => o.toProof(signatures[i], keyset)) }
}

// Build-time guard against the permanent-lock footgun: NUT-11 treats an absent/0/NaN locktime as permanent
// (refund key never activates). The mint clock is the real authority; this just refuses an obviously-bad value.
function assertFutureLocktime(locktime) {
  if (!Number.isFinite(locktime) || locktime <= 0) {
    throw new Error("locktime must be a positive unix-seconds integer")
  }
}
