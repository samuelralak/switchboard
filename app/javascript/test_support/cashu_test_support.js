import * as cashu from "@cashu/cashu-ts"
import { Wallet, createRandomSecretKey, getPubKeyFromPrivKey } from "@cashu/cashu-ts"
import * as escrow from "nostr/cashu_escrow"
import { mintLockAndReport, mintLockAndReportTier2 } from "nostr/order_funding"
import * as orderFunding from "nostr/order_funding"
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

// Mint `amount` sats and build a Tier-2 2-of-3 P2PK lock {consumer, provider, arbiter}; returns the consumer
// wallet, the three fresh keypairs, and the lock. Shared by the Tier-2 spike scenarios below.
async function tier2Lock(mint, amount, locktime) {
  const consumer = new Wallet(mint, { unit: "sat" })
  await escrow.ensureMintSupports(consumer)
  const consumerKp = newKeypair(), providerKp = newKeypair(), arbiterKp = newKeypair()

  const proofs = await mintTestSats(consumer, amount)
  const lock = await escrow.lockP2PK2of3({
    wallet: consumer, amount, proofs, consumerPubkey: consumerKp.pkHex, providerPubkey: providerKp.pkHex,
    arbiterPubkey: arbiterKp.pkHex, consumerRefundPubkey: consumerKp.pkHex, locktime,
  })

  return { consumer, consumerKp, providerKp, arbiterKp, lock }
}

const sigCount = (witness) => (escrow.parseWitness(witness).signatures || []).length
const totalOf = (proofs) => proofs.reduce((sum, p) => sum + Number(p.amount), 0)

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

  // After a successful redeem the locked proofs read SPENT (the condition the settlement controller checks
  // before resubmitting), and a naive second redeem is rejected by the mint -- the "proofs already spent"
  // bug the doRedeem idempotency guard exists to prevent.
  async doubleRedeemIsIdempotent(mint) {
    const consumer = new Wallet(mint, { unit: "sat" }), provider = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    await escrow.ensureMintSupports(provider)
    const providerKp = newKeypair(), consumerKp = newKeypair()

    const proofs = await mintTestSats(consumer, 64)
    const locktime = Math.floor(Date.now() / 1000) + 3600
    const lock = await escrow.lockHtlc({ wallet: consumer, amount: 64, proofs,
      providerPubkey: providerKp.pkHex, consumerRefundPubkey: consumerKp.pkHex, locktime })

    await escrow.redeemWithPreimage({ wallet: provider, lockedProofs: lock.lockedProofs,
      preimage: lock.preimage, providerPrivkey: providerKp.skHex })
    const states = await escrow.proofState({ wallet: provider, proofs: lock.lockedProofs })

    let reSwapThrew = false
    try {
      await escrow.redeemWithPreimage({ wallet: provider, lockedProofs: lock.lockedProofs,
        preimage: lock.preimage, providerPrivkey: providerKp.skHex })
    } catch (_) { reSwapThrew = true }

    return { allSpent: states.every((s) => s.state === "SPENT"), reSwapThrew }
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

  // --- Tier 2 (2-of-3 P2PK arbiter) merge gate ---------------------------------------------------------
  // Build a 2-of-3 lock, assert the on-wire secret shape (data is a signer + pubkeys + n_sigs=2), then the
  // happy path (consumer+provider co-sign) redeems the full amount and the SPENT witness carries 2 signatures.
  async tier2LockAndHappyRelease(mint) {
    const { consumer, consumerKp, providerKp, arbiterKp, lock } =
      await tier2Lock(mint, 64, Math.floor(Date.now() / 1000) + 3600)

    const secret = JSON.parse(lock.lockedProofs[0].secret)
    const tags = Object.fromEntries((secret[1].tags || []).map((t) => [ t[0], t.slice(1) ]))
    const xonly = (pk) => (pk && pk.length === 66 ? pk.slice(2) : pk)
    const signers = [ secret[1].data, ...(tags.pubkeys || []) ].filter(Boolean).map(xonly).sort()
    const expected = [ consumerKp.pkHex, providerKp.pkHex, arbiterKp.pkHex ].map(xonly).sort()

    const before = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })

    let signed = escrow.coSignProofs(lock.lockedProofs, consumerKp.skHex)
    signed = escrow.coSignProofs(signed, providerKp.skHex)
    const redeemed = await escrow.redeem2of3({ wallet: consumer, signedProofs: signed })

    const after = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    const spent = after.find((s) => s.state === "SPENT" && s.witness)

    return {
      kind: secret[0],
      dataNonEmpty: !!secret[1].data,
      signerSetMatches: JSON.stringify(signers) === JSON.stringify(expected),
      nSigs: (tags.n_sigs || [])[0],
      hasRefund: !!tags.refund,
      beforeUnspent: before.every((s) => s.state === "UNSPENT"),
      redeemedTotal: totalOf(redeemed.proofs),
      spent: after.every((s) => s.state === "SPENT"),
      witnessSigCount: spent ? sigCount(spent.witness) : 0,
    }
  },

  // Dispute resolved for the provider: the arbiter co-signs with the provider (2-of-3) and the funds release.
  async tier2DisputeForProvider(mint) {
    const { consumer, providerKp, arbiterKp, lock } =
      await tier2Lock(mint, 32, Math.floor(Date.now() / 1000) + 3600)

    let signed = escrow.coSignProofs(lock.lockedProofs, arbiterKp.skHex)
    signed = escrow.coSignProofs(signed, providerKp.skHex)
    const redeemed = await escrow.redeem2of3({ wallet: consumer, signedProofs: signed })

    const after = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return { redeemedTotal: totalOf(redeemed.proofs), spent: after.every((s) => s.state === "SPENT") }
  },

  // Dispute resolved for the consumer: the arbiter co-signs with the consumer (2-of-3) and the funds return.
  async tier2DisputeForConsumer(mint) {
    const { consumer, consumerKp, arbiterKp, lock } =
      await tier2Lock(mint, 32, Math.floor(Date.now() / 1000) + 3600)

    let signed = escrow.coSignProofs(lock.lockedProofs, arbiterKp.skHex)
    signed = escrow.coSignProofs(signed, consumerKp.skHex)
    const redeemed = await escrow.redeem2of3({ wallet: consumer, signedProofs: signed })

    const after = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return { redeemedTotal: totalOf(redeemed.proofs), spent: after.every((s) => s.state === "SPENT") }
  },

  // Timeout: after the locktime the consumer reclaims alone via the refund pathway (1 signature, no arbiter).
  async tier2TimeoutRefund(mint) {
    const { consumer, consumerKp, lock } = await tier2Lock(mint, 16, Math.floor(Date.now() / 1000) - 60)

    const refunded = await escrow.refund({ wallet: consumer, token: lock.token, consumerRefundPrivkey: consumerKp.skHex })
    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    const spent = states.find((s) => s.state === "SPENT" && s.witness)

    return {
      refundedTotal: totalOf(refunded.proofs),
      spent: states.some((s) => s.state === "SPENT"),
      witnessSigCount: spent ? sigCount(spent.witness) : null,
    }
  },

  // NEGATIVE: a single signature (1 of the required 2) cannot release the lock; the proofs stay UNSPENT.
  async tier2SingleSigRejected(mint) {
    const { consumer, consumerKp, lock } = await tier2Lock(mint, 16, Math.floor(Date.now() / 1000) + 3600)

    const signed = escrow.coSignProofs(lock.lockedProofs, consumerKp.skHex) // only 1 of 2
    let threw = false
    try {
      await escrow.redeem2of3({ wallet: consumer, signedProofs: signed })
    } catch (_) {
      threw = true
    }

    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return { threw, stillUnspent: states.every((s) => s.state === "UNSPENT") }
  },

  // NEGATIVE: the refund pathway is rejected before the locktime, so the consumer cannot reclaim early.
  async tier2RefundBeforeLocktimeRejected(mint) {
    const { consumer, consumerKp, lock } = await tier2Lock(mint, 16, Math.floor(Date.now() / 1000) + 3600)

    let threw = false
    try {
      await escrow.refund({ wallet: consumer, token: lock.token, consumerRefundPrivkey: consumerKp.skHex })
    } catch (_) {
      threw = true
    }

    const states = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })
    return { threw, stillUnspent: states.every((s) => s.state === "UNSPENT") }
  },

  // Derive the compressed pubkey for a FIXED private key via cashu-ts (@noble/curves), so a Ruby test can
  // assert Escrow::ArbiterSigner derives the identical point (the arbiter key must match across languages).
  async arbiterPubkeyDerivation() {
    const fixed = "11".repeat(32)
    const skBytes = new Uint8Array(fixed.match(/../g).map((h) => parseInt(h, 16)))
    return { pubkey: toHex(getPubKeyFromPrivKey(skBytes)) }
  },

  // Cross-language: the browser builds a Tier-2 funding report (order_funding.js) against the real mint and
  // the Ruby Orders::Funding accepts it. The arbiter key is FIXED to match the Ruby test's TEST_ARBITER_PRIVKEY.
  async tier2FundReport(mint) {
    const amount = 8
    const consumer = new Wallet(mint, { unit: "sat" })
    const arbiterSk = "22".repeat(32)
    const arbiterPubkey = toHex(getPubKeyFromPrivKey(new Uint8Array(arbiterSk.match(/../g).map((h) => parseInt(h, 16)))))
    const provider = newKeypair(), consumerKp = newKeypair()
    const locktime = Math.floor(Date.now() / 1000) + 4 * 86400 // clears the Tier-2 min lead

    const { payload, token } = await mintLockAndReportTier2({
      wallet: consumer, mintUrl: mint, amount, consumerPubkey: consumerKp.pkHex, providerPubkey: provider.pkHex,
      arbiterPubkey, consumerRefundPubkey: consumerKp.pkHex, locktime,
    })

    return { amount, payload, arbiterPubkey, tokenOk: /^cashu/.test(token) }
  },

  // SERVER-ARBITER-SIGN SPIKE phase 1: lock a 2-of-3 to {consumer, provider, FIXED arbiter "33"*32}, the
  // PROVIDER co-signs (one of the two required sigs), and return the partially-signed proofs + their secrets
  // so the RUBY test can produce the arbiter's signature. The arbiter privkey lives only in Ruby (the server).
  async tier2ServerSignBuild(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const consumerKp = newKeypair(), providerKp = newKeypair()
    const arbiterSk = "33".repeat(32)
    const arbiterPubkey = toHex(getPubKeyFromPrivKey(new Uint8Array(arbiterSk.match(/../g).map((h) => parseInt(h, 16)))))
    const locktime = Math.floor(Date.now() / 1000) + 3600

    const proofs = await mintTestSats(consumer, 32)
    const lock = await escrow.lockP2PK2of3({
      wallet: consumer, amount: 32, proofs, consumerPubkey: consumerKp.pkHex, providerPubkey: providerKp.pkHex,
      arbiterPubkey, consumerRefundPubkey: consumerKp.pkHex, locktime,
    })
    const signed = escrow.coSignProofs(lock.lockedProofs, providerKp.skHex) // the provider's signature (1 of 2)

    return {
      proofs: signed.map((p) => ({ ...p, witness: typeof p.witness === "string" ? p.witness : JSON.stringify(p.witness) })),
      secrets: signed.map((p) => p.secret),
    }
  },

  // SERVER-ARBITER-SIGN SPIKE phase 2: append the Ruby-produced arbiter signatures to each proof's witness and
  // redeem the 2-of-3 at the real mint. If the proofs end SPENT, the server-side Ruby signature was accepted.
  async tier2ServerSignRedeem(mint, args) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)

    const signed = args.proofs.map((proof, i) => {
      const existing = escrow.parseWitness(proof.witness).signatures || []
      return { ...proof, witness: JSON.stringify({ signatures: [ ...existing, args.arbiterSigs[i] ] }) }
    })
    const redeemed = await escrow.redeem2of3({ wallet: consumer, signedProofs: signed })
    const after = await escrow.proofState({ wallet: consumer, proofs: signed })

    return { redeemedTotal: totalOf(redeemed.proofs), spent: after.every((s) => s.state === "SPENT") }
  },

  // The order_settlement.js settlement layer (not the raw cashu_escrow primitives): verifyTier2Lock accepts a
  // genuine lock and rejects a wrong amount / a key not in the signer set; the happy path co-signs via
  // partySign (consumer then provider) and spends via redeemTier2.
  async tier2SettlementHelpers(mint) {
    const locktime = Math.floor(Date.now() / 1000) + 3600
    const { consumer, consumerKp, providerKp, arbiterKp, lock } = await tier2Lock(mint, 32, locktime)

    const verify = (overrides = {}) => settlement.verifyTier2Lock({
      wallet: consumer, proofs: lock.lockedProofs, providerPubkey: providerKp.pkHex,
      arbiterPubkey: arbiterKp.pkHex, amount: 32, expectedLocktime: locktime, ...overrides })
    const verified = await verify()
    const wrongAmount = await verify({ amount: 31 })
    const stranger = await verify({ providerPubkey: newKeypair().pkHex })
    const wrongLocktime = await verify({ expectedLocktime: locktime + 1 }) // a mismatched on-mint locktime

    let signed = settlement.partySign({ proofs: lock.lockedProofs, privkey: consumerKp.skHex })
    signed = settlement.partySign({ proofs: signed, privkey: providerKp.skHex })
    const redeemed = await settlement.redeemTier2({ wallet: consumer, signedProofs: signed })
    const after = await escrow.proofState({ wallet: consumer, proofs: lock.lockedProofs })

    return {
      verifyOk: verified.ok,
      wrongAmountRejected: !wrongAmount.ok,
      strangerRejected: !stranger.ok,
      wrongLocktimeRejected: !wrongLocktime.ok,
      redeemedTotal: totalOf(redeemed.proofs),
      spent: after.every((s) => s.state === "SPENT"),
    }
  },

  // Dispute redeem via order_settlement helpers, phase 1: lock to {consumer, provider, FIXED arbiter "33"*32};
  // the WINNER (provider) co-signs via partySign; return its proofs + secrets for Ruby to arbiter-sign.
  async tier2DisputeRedeemBuild(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const consumerKp = newKeypair(), providerKp = newKeypair()
    const arbiterSk = "33".repeat(32)
    const arbiterPubkey = toHex(getPubKeyFromPrivKey(new Uint8Array(arbiterSk.match(/../g).map((h) => parseInt(h, 16)))))

    const proofs = await mintTestSats(consumer, 32)
    const lock = await escrow.lockP2PK2of3({
      wallet: consumer, amount: 32, proofs, consumerPubkey: consumerKp.pkHex, providerPubkey: providerKp.pkHex,
      arbiterPubkey, consumerRefundPubkey: consumerKp.pkHex, locktime: Math.floor(Date.now() / 1000) + 3600,
    })
    const signed = settlement.partySign({ proofs: lock.lockedProofs, privkey: providerKp.skHex })

    return {
      proofs: signed.map((p) => ({ ...p, witness: typeof p.witness === "string" ? p.witness : JSON.stringify(p.witness) })),
      secrets: signed.map((p) => p.secret),
    }
  },

  // Phase 2: applyArbiterSignatures merges the Ruby arbiter sigs into the provider's witness, then redeemTier2
  // spends. Spent => the provider+arbiter 2-of-3 completes end to end through the order_settlement helpers.
  async tier2DisputeRedeemApply(mint, args) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)

    const quorum = settlement.applyArbiterSignatures(args.proofs, args.arbiterSigs)
    const redeemed = await settlement.redeemTier2({ wallet: consumer, signedProofs: quorum })
    const after = await escrow.proofState({ wallet: consumer, proofs: args.proofs })

    return { redeemedTotal: totalOf(redeemed.proofs), spent: after.every((s) => s.state === "SPENT") }
  },

  // Crash-safety (review finding): mintLockAndReportTier2 persists a LOCAL marker the instant funds lock,
  // BEFORE the report round-trip, so a crash there cannot orphan the lock. After it runs, IndexedDB holds a
  // marker with the token + proofs + lock fields (but no payload yet -- the full backup writes that), and
  // reportFromSaved re-derives the same report Ys from it. This is what lets the resume guard never re-mint.
  async tier2FundingCrashMarker(mint) {
    const consumer = new Wallet(mint, { unit: "sat" })
    await escrow.ensureMintSupports(consumer)
    const me = newKeypair(), providerKp = newKeypair()
    const arbiterSk = "33".repeat(32)
    const arbiterPubkey = toHex(getPubKeyFromPrivKey(new Uint8Array(arbiterSk.match(/../g).map((h) => parseInt(h, 16)))))
    const orderId = `crash-${toHex(createRandomSecretKey())}`

    const result = await mintLockAndReportTier2({
      wallet: consumer, mintUrl: mint, amount: 4, consumerPubkey: me.pkHex, providerPubkey: providerKp.pkHex,
      arbiterPubkey, consumerRefundPubkey: me.pkHex, locktime: Math.floor(Date.now() / 1000) + 3600, orderId,
    })
    const marker = await orderFunding.loadSecrets(orderId)
    const reReported = await orderFunding.reportFromSaved(consumer, marker)
    const ys = (proofs) => JSON.stringify(proofs.map((p) => p.y).sort())

    return {
      markerHasToken: !!marker?.token,
      markerHasProofs: (marker?.proofs || []).length > 0,
      markerHasNoPayload: !marker?.payload, // the crash marker precedes the full (with-payload) backup
      markerHasArbiterField: marker?.fields?.arbiter_pubkey === arbiterPubkey,
      reReportMatches: ys(reReported.proofs) === ys(result.payload.proofs),
    }
  },

  // Build a NIP-98 Authorization header with nip98.js (the client the dispute redeem uses), for the Ruby side
  // to feed through the real server verifier -- proves the client emits a server-acceptable kind-27235 event.
  async buildNip98Header(_mint, args) {
    const { NsecSigner } = await import("nostr/signer")
    const { nip98AuthHeader } = await import("nostr/nip98")
    const signer = NsecSigner.fromHex(args.privkey)
    const header = await nip98AuthHeader(signer, { url: args.url, method: args.method, body: args.body })

    return { header, pubkey: signer.getPublicKey() }
  },
}

window.CashuTest = { loaded: true, exports: Object.keys(cashu).sort() }
window.CashuEscrowTest = { loaded: true, Wallet, newKeypair, mintTestSats, scenarios, mintLockAndReport, ...escrow, ...settlement }
