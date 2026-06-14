import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// Post-funding escrow actions on the order page. Consumer: approve+release (reveal the preimage to the
// provider) or refund after the locktime. Provider: verify the delivered budget, then redeem once the
// consumer reveals. All crypto + keys stay in the browser (brief sec 6.3); Rails learns the outcome from
// the mint via the reconcile sweep, which broadcasts the new state back to this page.
export default class extends Controller {
  static targets = [
    "release", "refund", "verify", "redeem", "disputeRedeem", "restore",
    "status", "error", "payout", "payoutToken", "payoutAmount",
  ]
  static values = {
    orderId: String, mint: String, relays: String, own: String, peer: String,
    locktime: Number, amount: Number, hashlock: String, lockPubkey: String, settleUrl: String, releaseUrl: String,
    tier: String, arbiterPubkey: String, arbiterUrl: String,
  }

  // Re-surface a payout already saved on this device (after a reload, or on the settled order page) so the payee
  // can always re-copy their claimable token without re-settling.
  async connect() {
    if (!this.hasPayoutTarget) return

    const { loadPayout } = await import("nostr/order_funding")
    const payout = await loadPayout(this.orderIdValue)
    if (payout?.token) this.showPayout(payout)
  }

  release() { this.run(this.releaseTarget, () => this.doRelease()) }
  refund() { this.run(this.refundTarget, () => this.doRefund()) }
  verify() { this.run(this.verifyTarget, () => this.doVerify()) }
  redeem() { this.run(this.redeemTarget, () => this.doRedeem()) }
  disputeRedeem() { this.run(this.disputeRedeemTarget, () => this.doDisputeRedeem()) }
  restore() { this.run(this.restoreTarget, () => this.doRestorePayout()) }

  get isTier2() { return this.tierValue === TIER2_ARBITER }

  // Consumer authorizes the release. Tier-1: reveal the preimage. Tier-2: co-sign the locked proofs with the
  // consumer escrow key and hand them to the provider (one of the two required signatures).
  async doRelease() {
    if (this.isTier2) return this.doReleaseTier2()

    const saved = await this.loadSecrets()
    if (!saved?.preimage) throw new Error("Your release secret is not on this device. Use the device you funded from.")

    const { sendEscrowMessage } = await import("nostr/escrow_messages")
    const rumor = await sendEscrowMessage({ ...(await this.peerChannel()), orderId: this.orderIdValue,
      type: "preimage-reveal", data: { preimage: saved.preimage } })

    await this.recordRelease(rumor) // reflect "released, awaiting redemption" now, before the provider redeems
    this.setStatus("Released. The provider can now redeem; this order settles shortly.")
    return "latch" // the preimage is out; re-revealing is pointless and the panel repaints via broadcast
  }

  // Tier-2 happy-path release: the consumer co-signs the locked proofs (1 of the 2-of-3) and ships them to
  // the provider over NIP-17; the provider adds its own signature and redeems. No preimage, no arbiter.
  async doReleaseTier2() {
    const saved = await this.loadSecrets()
    if (!saved?.proofs?.length) throw new Error("Your escrow proofs are not on this device. Use the device you funded from.")

    const { partySign } = await import("nostr/order_settlement")
    const signed = partySign({ proofs: saved.proofs, privkey: (await this.identity()).privkeyHex })

    const { sendEscrowMessage } = await import("nostr/escrow_messages")
    const rumor = await sendEscrowMessage({ ...(await this.peerChannel()), orderId: this.orderIdValue,
      type: "cosign", data: { proofs: signed } })

    await this.recordRelease(rumor)
    this.setStatus("Released. The provider can redeem with your co-signature; this order settles shortly.")
    return "latch"
  }

  // Record the observable release assertion (the reveal event id + its time, never the preimage) so the
  // order reflects the release immediately. Best-effort: settlement still lands when the provider redeems.
  async recordRelease(rumor) {
    if (!this.hasReleaseUrlValue || !this.releaseUrlValue) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    await fetch(this.releaseUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ release: { reveal_event_id: rumor.id, released_at: rumor.created_at } }),
    })
  }

  // Consumer reclaims the budget after the locktime if no release happened.
  async doRefund() {
    // An absent/0 locktime must BLOCK the refund, not bypass the guard (a falsy && short-circuits).
    if (!Number.isFinite(this.locktimeValue) || this.locktimeValue <= 0) throw new Error("Refund needs a valid lock expiry.")
    if (Date.now() / 1000 < this.locktimeValue) throw new Error("Refund is available after the lock expires.")

    const saved = await this.loadOrRestoreSecrets()
    if (!saved?.token) throw new Error("Your escrow token could not be found or restored on this device.")

    const { refundExpired } = await import("nostr/order_settlement")
    const settled = await refundExpired({ wallet: await this.wallet(), token: saved.token, refundPrivkey: (await this.identity()).privkeyHex })
    await this.keepPayout(settled.proofs, "refunded") // CAPTURE the refunded ecash before anything else; it is the consumer's money
    await this.settle() // the proofs are now spent at the mint; have Rails register the refund now

    this.setStatus("Refund claimed. Your payout is below.")
    return "latch"
  }

  // Provider confirms the delivered budget is locked to them and unspent before doing the work.
  async doVerify() {
    if (this.isTier2) return this.doVerifyTier2()

    const delivery = await this.fetchDelivery()
    const { verifyDeliveredProofs } = await import("nostr/order_settlement")
    const result = await verifyDeliveredProofs({ wallet: await this.wallet(), proofs: delivery.proofs,
      hashlock: this.hashlockValue, lockPubkey: this.lockPubkeyValue, amount: this.amountValue })

    if (!result.ok) throw new Error(`Could not verify the escrow: ${result.reason}`)

    this.setStatus("Verified: the budget is locked to you and unspent. You can safely deliver the work.")
  }

  // Provider confirms the tier-2 budget is a 2-of-3 locked to them + the platform arbiter, unspent, and with
  // the on-mint locktime EQUAL to the one Rails recorded (so the consumer cannot lock a short locktime while
  // reporting a long one and refund-steal after delivery).
  async doVerifyTier2() {
    const delivery = await this.fetchDelivery()
    const { verifyTier2Lock } = await import("nostr/order_settlement")
    const result = await verifyTier2Lock({ wallet: await this.wallet(), proofs: delivery.proofs,
      providerPubkey: (await this.identity()).pubkeyHex, arbiterPubkey: this.arbiterPubkeyValue,
      amount: this.amountValue, expectedLocktime: this.locktimeValue })

    if (!result.ok) throw new Error(`Could not verify the escrow: ${result.reason}`)

    this.setStatus("Verified: a 2-of-3 escrow locked to you and the platform arbiter, unspent. Safe to deliver.")
  }

  // Provider redeems once the consumer has authorized the release.
  async doRedeem() {
    if (this.isTier2) return this.doRedeemTier2()

    const delivery = await this.fetchDelivery()
    const reveal = await this.latest("preimage-reveal")
    if (!reveal?.data?.preimage) throw new Error("The consumer has not approved the release yet.")

    const wallet = await this.wallet()

    // Idempotency: if the proofs are already gone (we redeemed, or the consumer refunded), do NOT resubmit
    // them to the mint -- that is the "proofs already spent" error. Just have Rails re-derive state.
    if (!(await this.allUnspent(wallet, delivery.proofs))) return this.alreadySettled()

    const { redeemDelivered } = await import("nostr/order_settlement")
    const settled = await redeemDelivered({ wallet, proofs: delivery.proofs,
      preimage: reveal.data.preimage, providerPrivkey: (await this.identity()).privkeyHex })
    await this.keepPayout(settled.proofs, "released") // CAPTURE the redeemed ecash before anything else; it is the provider's money
    await this.settle() // the proofs are now spent at the mint; have Rails register the release now

    this.setStatus("Redeemed. Your payout is below.")
    return "latch"
  }

  // Tier-2 happy-path redeem: combine the consumer's co-signature (over NIP-17) with the provider's own to
  // make the 2-of-3, then spend. No arbiter, no preimage.
  async doRedeemTier2() {
    const cosign = await this.latest("cosign")
    if (!cosign?.data?.proofs?.length) throw new Error("The consumer has not released (co-signed) yet.")

    const wallet = await this.wallet()
    if (!(await this.allUnspent(wallet, cosign.data.proofs))) return this.alreadySettled()

    const { partySign, redeemTier2 } = await import("nostr/order_settlement")
    const signed = partySign({ proofs: cosign.data.proofs, privkey: (await this.identity()).privkeyHex })
    const settled = await redeemTier2({ wallet, signedProofs: signed })
    await this.keepPayout(settled.proofs, "released") // CAPTURE the redeemed ecash before anything else
    await this.settle()

    this.setStatus("Redeemed with the consumer's co-signature. Your payout is below.")
    return "latch"
  }

  // Winning party of a RULED dispute completes the spend: co-sign the locked proofs with the winner's escrow
  // key, fetch the platform arbiter's co-signatures (NIP-98), merge to the 2-of-3, redeem. The arbiter
  // endpoint authorizes only the ruled winner; the winner co-signs with the ESCROW key but authenticates the
  // arbiter call with the LOGIN key (two distinct keys, both held by this party).
  async doDisputeRedeem() {
    const wallet = await this.wallet()
    const proofs = await this.disputeProofs()
    if (!(await this.allUnspent(wallet, proofs))) return this.alreadySettled()

    const { partySign, applyArbiterSignatures, redeemTier2 } = await import("nostr/order_settlement")
    const signed = partySign({ proofs, privkey: (await this.identity()).privkeyHex })
    const arbiterSigs = await this.fetchArbiterSignatures(proofs.map((proof) => proof.secret))
    const settled = await redeemTier2({ wallet, signedProofs: applyArbiterSignatures(signed, arbiterSigs) })
    await this.keepPayout(settled.proofs, "released") // CAPTURE the redeemed ecash before anything else
    await this.settle()

    this.setStatus("Redeemed with the platform arbiter's co-signature. Your payout is below.")
    return "latch"
  }

  // The winner holds the locked proofs: the consumer from its funding backup (local, or restored from the
  // relay self-DM after device loss), the provider from the NIP-17 token-delivery it received at funding.
  async disputeProofs() {
    const saved = await this.loadOrRestoreSecrets()
    if (saved?.proofs?.length) return saved.proofs

    return (await this.fetchDelivery()).proofs
  }

  // Local IndexedDB first, then the NIP-44 self-encrypted relay backup made at funding (device-loss recovery).
  // The consumer's backup carries {token, proofs}; the provider made none (it has the delivery instead), so
  // this returns null for the provider and callers fall back to fetchDelivery.
  async loadOrRestoreSecrets() {
    const local = await this.loadSecrets()
    if (local?.proofs?.length || local?.token) return local

    const { restoreSecretsFromRelay } = await import("nostr/order_funding")
    return restoreSecretsFromRelay({ signer: await this.signer(), ownPubkey: this.ownValue, relays: this.relays(), orderId: this.orderIdValue })
  }

  // POST the locked proofs' secrets to the platform arbiter (NIP-98, login-key authed) -> one BIP-340
  // signature per secret, in order. An opaque non-2xx means the caller is not the ruling winner.
  async fetchArbiterSignatures(secrets) {
    const { nip98Fetch } = await import("nostr/nip98")
    const response = await nip98Fetch(this.arbiterUrlValue, { signer: await this.signer(), method: "POST", json: { secrets } })
    if (!response.ok) throw new Error("The platform arbiter signature is not available for this order.")

    return (await response.json()).signatures
  }

  // Proofs all UNSPENT at the mint? (idempotency precheck before any spend.)
  async allUnspent(wallet, proofs) {
    const { proofState } = await import("nostr/cashu_escrow")
    const states = await proofState({ wallet, proofs })

    return states.every((state) => state.state === "UNSPENT")
  }

  async alreadySettled() {
    await this.settle()
    this.setStatus("Already settled at the mint. This order is reconciling.")
    return "latch"
  }

  // --- payout: the redeemed/refunded ecash is the payee's money; capture, back up, and surface it ---

  // Persist + back up the freshly settled proofs and surface a claimable token. Called the instant a redeem or
  // refund returns its proofs -- they carry random, un-derivable secrets, so dropping them would burn the funds.
  async keepPayout(proofs, kind) {
    const { keepPayout } = await import("nostr/order_funding")
    const payout = await keepPayout({
      signer: await this.signer(), ownPubkey: this.ownValue, relays: this.relays(),
      orderId: this.orderIdValue, mint: this.mintValue, proofs, kind,
    })
    this.showPayout(payout)
  }

  // Cross-device recovery: restore the payout token from the encrypted relay backup when local state is gone.
  async doRestorePayout() {
    const { restorePayoutFromRelay } = await import("nostr/order_funding")
    const payout = await restorePayoutFromRelay({ signer: await this.signer(), ownPubkey: this.ownValue, relays: this.relays(), orderId: this.orderIdValue })
    if (!payout?.token) throw new Error("No payout backup was found for this order on your relays.")

    this.showPayout(payout)
    this.setStatus("Payout restored from your relay backup.")
    return "latch"
  }

  // Reveal the payout panel with the claimable token + amount (idempotent; safe to call again on reload).
  showPayout({ token, amount }) {
    if (!this.hasPayoutTarget || !token) return

    this.payoutTokenTarget.value = token
    if (this.hasPayoutAmountTarget) this.payoutAmountTarget.textContent = String(amount ?? "")
    this.payoutTarget.classList.remove("hidden")
  }

  copyPayout() {
    navigator.clipboard?.writeText(this.payoutTokenTarget.value)
  }

  // Ask Rails to re-derive the order's state from the mint now (post-spend), so settlement registers
  // immediately instead of waiting for the reconcile sweep. Best-effort: the sweep backstops a failure.
  async settle() {
    if (!this.hasSettleUrlValue) return

    const token = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch(this.settleUrlValue, { method: "POST", headers: { "X-CSRF-Token": token || "" } })
    } catch { /* the reconcile sweep backstops a transient failure */ }
  }

  async fetchDelivery() {
    const message = await this.latest("token-delivery")
    if (!message?.data?.proofs) throw new Error("The consumer has not delivered the locked budget yet.")

    return message.data
  }

  async latest(type) {
    const { latestEscrowMessage } = await import("nostr/escrow_messages")
    return latestEscrowMessage({ signer: await this.signer(), ownPubkey: this.ownValue, relays: this.relays(),
      orderId: this.orderIdValue, type, from: this.peerValue })
  }

  async loadSecrets() {
    const { loadSecrets } = await import("nostr/order_funding")
    return loadSecrets(this.orderIdValue)
  }

  async identity() {
    const { ensureEscrowIdentity } = await import("nostr/escrow_identity")
    return ensureEscrowIdentity({ accountPubkey: this.ownValue, signer: await this.signer(), relays: this.relays(), mints: [ this.mintValue ] })
  }

  async peerChannel() {
    return { signer: await this.signer(), ownPubkey: this.ownValue, peerPubkey: this.peerValue, relays: this.relays() }
  }

  async signer() {
    this._signer ||= await ensureSignerFor(this.ownValue, { prompt: true })
    if (!this._signer) throw new Error("Unlock your signer to continue.")

    return this._signer
  }

  async wallet() {
    const { Wallet } = await import("@cashu/cashu-ts")
    return new Wallet(this.mintValue, { unit: "sat" })
  }

  relays() { return JSON.parse(this.relaysValue) }

  // A spend is irreversible, and the state flip back to this page arrives via an async Turbo broadcast that
  // lands AFTER this returns. An action that spent (or settled) returns "latch" to keep its button disabled
  // so a second click cannot resubmit now-spent proofs to the mint ("proofs already spent").
  async run(button, action) {
    button.disabled = true
    this.clearError()
    let latch = false

    try {
      latch = (await action()) === "latch"
    } catch (error) {
      this.showError(error?.message || "Something went wrong.")
    } finally {
      if (!latch) button.disabled = false
    }
  }

  setStatus(text) { this.statusTarget.textContent = text }
  showError(text) { this.errorTarget.textContent = text; this.errorTarget.classList.remove("hidden") }
  clearError() { this.errorTarget.textContent = ""; this.errorTarget.classList.add("hidden") }
}

// Mirrors Orders::Tiers::TIER2_ARBITER; the order's tier is rendered into data-settlement-tier-value.
const TIER2_ARBITER = "tier2_arbiter"
