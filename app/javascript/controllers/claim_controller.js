import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// Claim an open request. The claimer becomes the provider, so escrow is ensured AT CLAIM TIME: publish
// the claimer's NIP-61 kind:10019 escrow key (so the request author can later lock the budget to them),
// then submit the Turbo claim form (POST /orders with the request coordinate). Keys stay in the browser.
export default class extends Controller {
  static targets = [ "form", "button", "error" ]
  static values = { pubkey: String, relays: String, mint: String }

  async claim() {
    this.buttonTarget.disabled = true
    this.clearError()
    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) throw new Error("Unlock your signer to claim this request.")

      const { ensureEscrowIdentity } = await import("nostr/escrow_identity")
      await ensureEscrowIdentity({
        accountPubkey: this.pubkeyValue, signer, relays: JSON.parse(this.relaysValue),
        mints: this.mintValue ? [ this.mintValue ] : [],
      })

      this.formTarget.requestSubmit()
    } catch (error) {
      this.showError(error?.message || "Couldn't claim this request. Please try again.")
      this.buttonTarget.disabled = false
    }
  }

  showError(text) {
    this.errorTarget.textContent = text
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}
