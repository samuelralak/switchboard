import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"
import { sendOrderRequest } from "nostr/order_envelope"

// Consumer-side: seal the filled service inputs + an optional note to the provider over NIP-17
// (order_envelope.js). The keys and the request content stay in the browser; Rails never sees them. The
// "sent" flag is per-tab (the server can't observe an end-to-end message), so a fresh tab may re-send --
// the provider's view takes the latest envelope, which is harmless.
const sentKey = (orderId) => `switchboard.order-request.${orderId}`

export default class extends Controller {
  static values = { orderId: String, coordinate: String, peer: String, own: String, relays: Array }
  static targets = [ "form", "field", "note", "submit", "status", "error" ]

  connect() {
    if (this.alreadySent()) this.showSent()
  }

  async send(event) {
    event?.preventDefault() // the simple_form <form> submits to "#"; the request goes out over NIP-17, not HTTP
    this.clearError()
    const missing = this.fieldTargets.find((field) => field.dataset.required === "true" && !field.value.trim())
    if (missing) return this.showError(`${missing.dataset.label || "A required field"} is required.`)

    this.submitTarget.disabled = true
    this.setStatus("Encrypting and sending…")
    try {
      const signer = await ensureSignerFor(this.ownValue, { prompt: true })
      if (!signer) throw new Error("Unlock your signer to send your request.")
      await sendOrderRequest({
        signer, ownPubkey: this.ownValue, peerPubkey: this.peerValue, relays: this.relaysValue,
        orderId: this.orderIdValue, coordinate: this.coordinateValue,
        inputs: this.collect(), note: this.hasNoteTarget ? this.noteTarget.value.trim() : "",
      })
      this.markSent()
      this.showSent()
    } catch (error) {
      this.submitTarget.disabled = false
      this.setStatus("")
      this.showError(error?.message || "Couldn't send your request. Please try again.")
    }
  }

  // The filled fields as [{ label, value }], dropping the ones left blank.
  collect() {
    return this.fieldTargets
      .map((field) => ({ label: field.dataset.label || "", value: field.value.trim() }))
      .filter((entry) => entry.value)
  }

  showSent() {
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    this.setStatus("Request sent to the provider.")
  }

  alreadySent() {
    try { return sessionStorage.getItem(sentKey(this.orderIdValue)) === "1" } catch { return false }
  }

  markSent() {
    try { sessionStorage.setItem(sentKey(this.orderIdValue), "1") } catch { /* private mode: re-send is harmless */ }
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}
