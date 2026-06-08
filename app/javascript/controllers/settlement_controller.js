import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// Post-funding escrow actions on the order page. Consumer: approve+release (reveal the preimage to the
// provider) or refund after the locktime. Provider: verify the delivered budget, then redeem once the
// consumer reveals. All crypto + keys stay in the browser (brief sec 6.3); Rails learns the outcome from
// the mint via the reconcile sweep, which broadcasts the new state back to this page.
export default class extends Controller {
  static targets = [ "release", "refund", "verify", "redeem", "status", "error" ]
  static values = {
    orderId: String, mint: String, relays: String, own: String, peer: String,
    locktime: Number, amount: Number, hashlock: String, lockPubkey: String, settleUrl: String,
  }

  release() { this.run(this.releaseTarget, () => this.doRelease()) }
  refund() { this.run(this.refundTarget, () => this.doRefund()) }
  verify() { this.run(this.verifyTarget, () => this.doVerify()) }
  redeem() { this.run(this.redeemTarget, () => this.doRedeem()) }

  // Consumer reveals the preimage to the provider, authorizing the release.
  async doRelease() {
    const saved = await this.loadSecrets()
    if (!saved?.preimage) throw new Error("Your release secret is not on this device. Use the device you funded from.")
    const { sendEscrowMessage } = await import("nostr/escrow_messages")
    await sendEscrowMessage({ ...(await this.peerChannel()), orderId: this.orderIdValue,
      type: "preimage-reveal", data: { preimage: saved.preimage } })
    this.setStatus("Released. The provider can now redeem; this order settles shortly.")
  }

  // Consumer reclaims the budget after the locktime if no release happened.
  async doRefund() {
    if (this.locktimeValue && Date.now() / 1000 < this.locktimeValue) throw new Error("Refund is available after the lock expires.")
    const saved = await this.loadSecrets()
    if (!saved?.token) throw new Error("Your escrow token is not on this device. Use the device you funded from.")
    const { refundExpired } = await import("nostr/order_settlement")
    await refundExpired({ wallet: await this.wallet(), token: saved.token, refundPrivkey: (await this.identity()).privkeyHex })
    await this.settle() // the proofs are now spent at the mint; have Rails register the refund now
    this.setStatus("Refund claimed. This order is settling to refunded.")
  }

  // Provider confirms the delivered budget is locked to them and unspent before doing the work.
  async doVerify() {
    const delivery = await this.fetchDelivery()
    const { verifyDeliveredProofs } = await import("nostr/order_settlement")
    const result = await verifyDeliveredProofs({ wallet: await this.wallet(), proofs: delivery.proofs,
      hashlock: this.hashlockValue, lockPubkey: this.lockPubkeyValue, amount: this.amountValue })
    if (!result.ok) throw new Error(`Could not verify the escrow: ${result.reason}`)
    this.setStatus("Verified: the budget is locked to you and unspent. You can safely deliver the work.")
  }

  // Provider redeems once the consumer has revealed the preimage.
  async doRedeem() {
    const delivery = await this.fetchDelivery()
    const reveal = await this.latest("preimage-reveal")
    if (!reveal?.data?.preimage) throw new Error("The consumer has not approved the release yet.")
    const { redeemDelivered } = await import("nostr/order_settlement")
    await redeemDelivered({ wallet: await this.wallet(), proofs: delivery.proofs,
      preimage: reveal.data.preimage, providerPrivkey: (await this.identity()).privkeyHex })
    await this.settle() // the proofs are now spent at the mint; have Rails register the release now
    this.setStatus("Redeemed. The budget is yours; this order is settling to released.")
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

  async run(button, action) {
    button.disabled = true
    this.clearError()
    try {
      await action()
    } catch (error) {
      this.showError(error?.message || "Something went wrong.")
    } finally {
      button.disabled = false
    }
  }

  setStatus(text) { this.statusTarget.textContent = text }
  showError(text) { this.errorTarget.textContent = text; this.errorTarget.classList.remove("hidden") }
  clearError() { this.errorTarget.textContent = ""; this.errorTarget.classList.add("hidden") }
}
