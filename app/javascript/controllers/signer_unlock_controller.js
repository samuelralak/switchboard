import { Controller } from "@hotwired/stimulus"
import { unlockNsec, resolveUnlock, cancelUnlock, hasPendingUnlock } from "nostr/signer_store"

// Re-hydrates a saved nsec signer after a hard reload (the SignerRegistry is in-memory and does not
// survive one). When the store requests an unlock (signer:unlock-requested), this reveals a passphrase
// overlay, decrypts the saved NIP-49 key client-side, registers the resulting signer, and resolves the
// pending request. Dismissing the overlay cancels it so the caller falls back to a "connect" message.
export default class extends Controller {
  static targets = ["overlay", "passphrase", "status"]
  static values = { accountPubkey: String } // which account's saved key this dialog unlocks

  connect() {
    this.onRequest = () => this.open()
    document.addEventListener("signer:unlock-requested", this.onRequest)
    // A consumer may have requested an unlock before this controller connected (hard-reload race); if a
    // request is already pending, open now so the prompt is not missed.
    if (hasPendingUnlock()) this.open()
  }

  disconnect() {
    document.removeEventListener("signer:unlock-requested", this.onRequest)
  }

  open() {
    this.unlocked = false
    this.setStatus("")
    if (this.hasPassphraseTarget) this.passphraseTarget.value = ""
    this.overlayTarget.hidden = false
    requestAnimationFrame(() => this.passphraseTarget?.focus())
  }

  // Dismiss without unlocking (close button, backdrop click, Esc): cancel the pending request.
  cancel(event) {
    event?.preventDefault()
    this.close()
    if (!this.unlocked) cancelUnlock()
  }

  close() {
    this.overlayTarget.hidden = true
    if (this.hasPassphraseTarget) this.passphraseTarget.value = ""
  }

  keydown(event) {
    if (event.key === "Escape" && !this.overlayTarget.hidden) this.cancel(event)
  }

  async submit(event) {
    event.preventDefault()
    const passphrase = this.passphraseTarget.value
    if (!passphrase) return this.setStatus("Enter your passphrase.")

    this.setStatus("Unlocking…")
    let signer
    try {
      signer = await unlockNsec(passphrase, this.accountPubkeyValue)
    } catch (error) {
      // unlockNsec throws a clean, user-meaningful message for each case (bad passphrase vs library-load
      // failure vs no-saved-key), so surface it rather than always blaming the passphrase.
      return this.setStatus(error.message || "Incorrect passphrase.")
    }
    this.unlocked = true
    resolveUnlock(signer)
    this.close()
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
