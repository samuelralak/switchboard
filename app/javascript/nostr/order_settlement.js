import { ensureMintSupports, redeemWithPreimage, refund, proofState } from "nostr/cashu_escrow"

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

// Consumer reclaims the backed-up token after the locktime (signature only, no preimage).
export async function refundExpired({ wallet, token, refundPrivkey }) {
  if (!HEX64.test(refundPrivkey)) throw new Error("refund privkey must be 64-hex")

  await ensureMintSupports(wallet) // load keysets; self-contained on a fresh page
  return refund({ wallet, token, consumerRefundPrivkey: refundPrivkey })
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

// The x-only tail of a SEC1 key, so a 02/03-prefixed compare is parity-agnostic (cashu signs over x-only).
const xonly = (pubkey) => String(pubkey).slice(-64)
