import { ensureMintSupports, redeemWithPreimage, refund, proofState, coSignProofs, redeem2of3, parseWitness } from "nostr/cashu_escrow"

// Browser-side settlement of a funded HTLC escrow (brief sec 9-10). The provider receives the locked
// proofs over NIP-17, verifies they are genuinely locked to them and unspent before doing the work,
// then redeems once the consumer reveals the preimage. The consumer refunds after the locktime if the
// work never arrives. Rails learns the outcome from the mint (reconcile), never from a call here.

const HEX64 = /^[0-9a-f]{64}$/

// Verify delivered proofs before doing the work: unspent at the mint, summing to the order amount, and
// HTLC-locked to THIS provider with the order's hashlock and a still-future locktime. Returns { ok, reason }.
export async function verifyDeliveredProofs({ wallet, proofs, hashlock, lockPubkey, amount }) {
  await ensureMintSupports(wallet)
  if (!Array.isArray(proofs) || proofs.length === 0) return { ok: false, reason: "no proofs delivered" }

  const sum = proofs.reduce((total, proof) => total + Number(proof.amount), 0)
  if (sum !== amount) return { ok: false, reason: `proofs sum ${sum} != order amount ${amount}` }

  const now = Math.floor(Date.now() / 1000)
  for (const proof of proofs) {
    const terms = parseHtlc(proof.secret)
    if (!terms) return { ok: false, reason: "a proof is not an HTLC lock" }
    if (terms.hashlock !== hashlock) return { ok: false, reason: "hashlock does not match the order" }
    if (!terms.pubkeys.some((pubkey) => xonly(pubkey) === xonly(lockPubkey))) return { ok: false, reason: "not locked to you" }
    if (!(terms.locktime > now)) return { ok: false, reason: "the locktime has already passed" }
  }

  const states = await proofState({ wallet, proofs })
  if (!states.every((state) => state.state === "UNSPENT")) return { ok: false, reason: "the proofs are not unspent" }

  return { ok: true }
}

// Provider redeems delivered proofs once the consumer has revealed the preimage.
export async function redeemDelivered({ wallet, proofs, preimage, providerPrivkey }) {
  if (!HEX64.test(preimage)) throw new Error("preimage must be 64-hex")
  if (!HEX64.test(providerPrivkey)) throw new Error("provider privkey must be 64-hex")

  await ensureMintSupports(wallet) // load keysets; self-contained on a fresh page
  return redeemWithPreimage({ wallet, lockedProofs: proofs, preimage, providerPrivkey })
}

// Consumer reclaims the backed-up token after the locktime (signature only, no preimage). Tier-agnostic:
// a tier-1 HTLC and a tier-2 2-of-3 both set the consumer as the sole post-locktime refund key.
export async function refundExpired({ wallet, token, refundPrivkey }) {
  if (!HEX64.test(refundPrivkey)) throw new Error("refund privkey must be 64-hex")

  await ensureMintSupports(wallet) // load keysets; self-contained on a fresh page
  return refund({ wallet, token, consumerRefundPrivkey: refundPrivkey })
}

// --- Tier 2: arbiter-mediated 2-of-3 P2PK settlement ----------------------------------------------------

// Verify a delivered Tier-2 lock before working: unspent, summing to the order amount, a 2-of-3 P2PK whose
// signer set includes BOTH the provider's own key and the platform arbiter (so a ruling can pay the
// provider even if the consumer vanishes), with a refund pathway and a locktime that EQUALS the one Rails
// recorded (and is still future). Returns { ok, reason }. The locktime equality is load-bearing: Rails only
// validates the REPORTED locktime (it cannot read the on-mint secret), so a malicious consumer could lock a
// near-immediate locktime on the mint while reporting a long one to Rails and refund-steal right after
// delivery. Binding the on-mint locktime to the recorded value closes that. (The consumer's exact key is not
// asserted -- the provider only needs to confirm it can be paid.)
export async function verifyTier2Lock({ wallet, proofs, providerPubkey, arbiterPubkey, amount, expectedLocktime }) {
  await ensureMintSupports(wallet)
  if (!Array.isArray(proofs) || proofs.length === 0) return { ok: false, reason: "no proofs delivered" }

  const sum = proofs.reduce((total, proof) => total + Number(proof.amount), 0)
  if (sum !== amount) return { ok: false, reason: `proofs sum ${sum} != order amount ${amount}` }

  const now = Math.floor(Date.now() / 1000)
  for (const proof of proofs) {
    const terms = parseP2PK(proof.secret)
    if (!terms) return { ok: false, reason: "a proof is not a P2PK lock" }
    if (terms.nSigs !== 2) return { ok: false, reason: "the lock is not a 2-of-3" }

    const signers = [ terms.data, ...terms.pubkeys ].map(xonly)
    if (!signers.includes(xonly(providerPubkey))) return { ok: false, reason: "not locked to you" }
    if (!signers.includes(xonly(arbiterPubkey))) return { ok: false, reason: "the platform arbiter is not a signer" }
    if (terms.refund.length === 0) return { ok: false, reason: "no refund pathway" }
    if (expectedLocktime && terms.locktime !== expectedLocktime) return { ok: false, reason: "the on-mint locktime does not match the recorded one" }
    if (!(terms.locktime > now)) return { ok: false, reason: "the locktime has already passed or opens too soon" }
  }

  const states = await proofState({ wallet, proofs })
  if (!states.every((state) => state.state === "UNSPENT")) return { ok: false, reason: "the proofs are not unspent" }

  return { ok: true }
}

// A party adds its escrow-key signature to each proof's 2-of-3 witness. Chainable across holders: the happy
// path gathers consumer + provider; a dispute gathers the winner + (via applyArbiterSignatures) the arbiter.
export function partySign({ proofs, privkey }) {
  if (!HEX64.test(privkey)) throw new Error("escrow privkey must be 64-hex")

  return coSignProofs(proofs, privkey)
}

// Merge the platform arbiter's detached signatures (one per proof, in order) into each proof's witness,
// preserving the signature already there (the winning party's), yielding the 2-of-3 quorum witness.
export function applyArbiterSignatures(proofs, signatures) {
  if (!Array.isArray(signatures) || signatures.length !== proofs.length) {
    throw new Error("expected one arbiter signature per proof")
  }

  return proofs.map((proof, i) => {
    const existing = parseWitness(proof.witness).signatures
    return { ...proof, witness: JSON.stringify({ signatures: [ ...existing, signatures[i] ] }) }
  })
}

// Spend a 2-of-3 whose proofs already carry both required signatures.
export async function redeemTier2({ wallet, signedProofs }) {
  await ensureMintSupports(wallet) // load keysets; self-contained on a fresh page
  return redeem2of3({ wallet, signedProofs })
}

// Parse a NUT-14 HTLC secret -> { hashlock, pubkeys, locktime, refund }, or null.
function parseHtlc(secret) {
  try {
    const [ kind, body ] = typeof secret === "string" ? JSON.parse(secret) : secret
    if (kind !== "HTLC" || !body) return null

    const tags = Object.fromEntries((body.tags || []).map(([ name, ...values ]) => [ name, values ]))
    return {
      hashlock: body.data,
      pubkeys: tags.pubkeys || [],
      locktime: Number((tags.locktime || [])[0]),
      refund: tags.refund || [],
    }
  } catch {
    return null
  }
}

// Parse a NUT-11 P2PK secret -> { data, pubkeys, nSigs, locktime, refund }, or null. The signer set is
// [data, ...pubkeys]; n_sigs is the release threshold (2 for a tier-2 2-of-3).
function parseP2PK(secret) {
  try {
    const [ kind, body ] = typeof secret === "string" ? JSON.parse(secret) : secret
    if (kind !== "P2PK" || !body) return null

    const tags = Object.fromEntries((body.tags || []).map(([ name, ...values ]) => [ name, values ]))
    return {
      data: body.data,
      pubkeys: tags.pubkeys || [],
      nSigs: Number((tags.n_sigs || [])[0]),
      locktime: Number((tags.locktime || [])[0]),
      refund: tags.refund || [],
    }
  } catch {
    return null
  }
}

// The x-only tail of a SEC1 key, so a 02/03-prefixed compare is parity-agnostic (cashu signs over x-only).
const xonly = (pubkey) => String(pubkey).slice(-64)
