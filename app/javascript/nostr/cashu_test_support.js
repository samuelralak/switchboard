import * as cashu from "@cashu/cashu-ts"
import { Wallet, createRandomSecretKey, getPubKeyFromPrivKey } from "@cashu/cashu-ts"
import * as escrow from "nostr/cashu_escrow"
import { mintLockAndReport } from "nostr/order_funding"
import * as settlement from "nostr/order_settlement"

// Test-only bridge: confirms @cashu/cashu-ts loads under the import map + CSP and drives the escrow module's
// lock/release/refund flow in-browser against a local mint, so the system test can assert in Ruby on plain
// result objects. Pinned but never loaded in production (only a system test injects it).

const toHex = (x) => (typeof x === "string" ? x : Array.from(x, (b) => b.toString(16).padStart(2, "0")).join(""))

// A fresh Cashu (secp256k1) keypair, hex-encoded. Test-only stand-in for the per-account wallet key.
function newKeypair() {
  const sk = createRandomSecretKey()
  return { skHex: toHex(sk), pkHex: toHex(getPubKeyFromPrivKey(sk)) }
}

// Mint test sats via the FakeWallet bolt11 flow (the local nutshell auto-pays the invoice). Returns proofs.
async function mintTestSats(wallet, amount) {
  const quote = await wallet.createMintQuoteBolt11(amount)
  let state = quote
  for (let i = 0; i < 60 && state.state !== "PAID"; i++) {
    await new Promise((r) => setTimeout(r, 200))
    state = await wallet.checkMintQuoteBolt11(quote.quote)
  }
  const minted = await wallet.mintProofsBolt11(amount, quote.quote)
  return minted?.proofs ?? minted
}

// End-to-end escrow flows the system test runs by name. Each takes the mint URL and returns a plain object
// of booleans/totals the Ruby side asserts on; they exercise the real escrow primitive (cashu_escrow.js).
const scenarios = {
  // Lock an HTLC, prove a wrong preimage cannot redeem, release with the real preimage, and confirm the
  // settled proof's NUT-07 witness reveals the preimage (the runtime's authoritative release signal).
  async lockReleaseReveal(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    const provider = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    await escrow.ensureMintSupports(provider)
    const providerKp = newKeypair(), consumerKp = newKeypair()

    const proofs = await mintTestSats(consumer, 64)
    const locktime = Math.floor(Date.now() / 1000) + 3600
    const lock = await escrow.lockHtlc({ wallet: consumer, amount: 64, proofs,
      providerPubkey: providerKp.pkHex, consumerRefundPubkey: consumerKp.pkHex, locktime })

    const before = await escrow.proofState({ wallet: provider, proofs: lock.lockedProofs })
    let negThrew = false
    try {
      await escrow.redeemWithPreimage({ wallet: provider, lockedProofs: lock.lockedProofs,
        preimage: "00".repeat(31) + "02", providerPrivkey: providerKp.skHex })
    } catch (_) { negThrew = true }
    const afterNeg = await escrow.proofState({ wallet: provider, proofs: lock.lockedProofs })

    const redeemed = await escrow.redeemWithPreimage({ wallet: provider, lockedProofs: lock.lockedProofs,
      preimage: lock.preimage, providerPrivkey: providerKp.skHex })
    const after = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    const spent = after.find((s) => s.state === "SPENT" && s.witness)

    return {
      tokenOk: /^cashu/.test(lock.token),
      preimageOk: /^[0-9a-f]{64}$/.test(lock.preimage),
      beforeUnspent: before.every((s) => s.state === "UNSPENT"),
      negThrew,
      stillUnspentAfterNeg: afterNeg.every((s) => s.state === "UNSPENT"),
      redeemedTotal: redeemed.proofs.reduce((sum, p) => sum + Number(p.amount), 0),
      revealedPreimage: spent ? escrow.parseWitness(spent.witness).preimage : null,
      expectedPreimage: lock.preimage,
    }
  },

  // Lock with an already-past locktime and confirm the consumer reclaims with a signature alone.
  async refundAfterLocktime(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const providerKp = newKeypair(), consumerKp = newKeypair()

    const proofs = await mintTestSats(consumer, 32)
    const past = Math.floor(Date.now() / 1000) - 60 // already expired -> immediately refundable
    const lock = await escrow.lockHtlc({ wallet: consumer, amount: 32, proofs,
      providerPubkey: providerKp.pkHex, consumerRefundPubkey: consumerKp.pkHex, locktime: past })

    const refunded = await escrow.refund({ wallet: consumer, token: lock.token,
      consumerRefundPrivkey: consumerKp.skHex })
    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return {
      refundedTotal: refunded.proofs.reduce((sum, p) => sum + Number(p.amount), 0),
      lockedSpent: states.some((s) => s.state === "SPENT"),
    }
  },

  // Lock with a future locktime and confirm a refund attempt is rejected, leaving the proofs untouched.
  async refundBeforeLocktime(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const providerKp = newKeypair(), consumerKp = newKeypair()

    const proofs = await mintTestSats(consumer, 16)
    const future = Math.floor(Date.now() / 1000) + 3600
    const lock = await escrow.lockHtlc({ wallet: consumer, amount: 16, proofs,
      providerPubkey: providerKp.pkHex, consumerRefundPubkey: consumerKp.pkHex, locktime: future })

    let threw = false
    try {
      await escrow.refund({ wallet: consumer, token: lock.token, consumerRefundPrivkey: consumerKp.skHex })
    } catch (_) { threw = true }
    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return { threw, stillUnspent: states.every((s) => s.state === "UNSPENT") }
  },

  // Drive the real funding orchestrator (order_funding.js) against the mint and return the report Rails
  // records, so the Ruby Orders::Funding contract can verify the browser output end-to-end. The local
  // FakeWallet auto-pays the invoice, so the poll resolves without a human paying.
  async fundReport(mint) {
    const amount = 8
    const consumer = new Wallet(mint, { unit: "sat" })
    const provider = newKeypair(), refund = newKeypair()
    const locktime = Math.floor(Date.now() / 1000) + 3600
    const { payload, token, preimage } = await mintLockAndReport({
      wallet: consumer, mintUrl: mint, amount,
      providerPubkey: provider.pkHex, consumerRefundPubkey: refund.pkHex, locktime,
    })
    return { amount, payload, tokenOk: /^cashu/.test(token), preimageOk: /^[0-9a-f]{64}$/.test(preimage) }
  },

  // Drive the consumer refund path through order_settlement.refundExpired against a past-locktime lock,
  // confirming the wrapper reclaims the budget and the locked proofs end SPENT.
  async settlementRefund(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const provider = newKeypair(), refund = newKeypair()
    const proofs = await mintTestSats(consumer, 16)
    const past = Math.floor(Date.now() / 1000) - 60
    const lock = await escrow.lockHtlc({ wallet: consumer, amount: 16, proofs,
      providerPubkey: provider.pkHex, consumerRefundPubkey: refund.pkHex, locktime: past })
    const refunded = await settlement.refundExpired({ wallet: consumer, token: lock.token, refundPrivkey: refund.skHex })
    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return {
      refundedTotal: refunded.proofs.reduce((sum, p) => sum + Number(p.amount), 0),
      lockedSpent: states.some((s) => s.state === "SPENT"),
    }
  },
}

window.CashuTest = { loaded: true, exports: Object.keys(cashu).sort() }
window.CashuEscrowTest = { loaded: true, Wallet, newKeypair, mintTestSats, scenarios, mintLockAndReport, ...escrow, ...settlement }
