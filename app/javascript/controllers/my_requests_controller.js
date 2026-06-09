import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// My-requests management: withdraw (status -> inactive) / re-post (status -> active) by re-signing the
// existing request event with the status tag flipped (preserving all data, reversible) and broadcasting
// it with the poster's key (identity-gated). The card flips in place; the public board catches up once a
// relay serves the new version back. Edit is a plain link to the prefilled form. Mirrors my_listings.
export default class extends Controller {
  static values = { pubkey: String, relays: Array }

  async toggleStatus(event) {
    const button = event.currentTarget
    const status = event.params.status // the status to apply
    const original = button.textContent
    button.disabled = true
    button.textContent = status === "inactive" ? "Withdrawing…" : "Re-posting…"
    this.clearError(button)
    this.clearNote(button)

    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) return this.fail(button, original, "Connect or unlock your signer.")

      const { setRequestStatus } = await import("nostr/request_publish")
      const result = await setRequestStatus(event.params.payload, status, signer, this.relaysValue)
      if (result.reached === 0) throw new Error("Couldn't reach any relay. Try again.")
      this.applyStatus(button, status, result.event)
    } catch (error) {
      this.fail(button, original, error.message)
    }
  }

  // Flip the card's status badge + the button in place (the next toggle reverses it), and refresh the
  // payload to the just-published version so a second toggle re-signs from it (monotonic created_at).
  applyStatus(button, appliedStatus, signedEvent) {
    const nowOpen = appliedStatus === "active"
    const badge = button.closest("[data-my-requests-card]")?.querySelector('[data-role="status"]')
    if (badge) {
      badge.textContent = nowOpen ? "open" : "withdrawn"
      badge.classList.toggle("text-lamp-settled", nowOpen)
      badge.classList.toggle("text-ink-faint", !nowOpen)
    }
    button.disabled = false
    button.dataset.myRequestsStatusParam = nowOpen ? "inactive" : "active"
    button.textContent = nowOpen ? "Withdraw" : "Re-post"
    if (signedEvent) {
      button.dataset.myRequestsPayloadParam = JSON.stringify({
        kind: signedEvent.kind, content: signedEvent.content, tags: signedEvent.tags, created_at: signedEvent.created_at,
      })
    }
    this.showNote(button) // reached >= 1 (reached === 0 threw before here): honest board-lag note
  }

  fail(button, original, message) {
    button.disabled = false
    button.textContent = original
    this.showError(button, message)
  }

  // The error belongs to the card whose toggle failed, so other cards stay quiet.
  errorSlot(button) {
    return button.closest("[data-my-requests-card]")?.querySelector("[data-my-requests-card-error]")
  }

  showError(button, message) {
    const slot = this.errorSlot(button)
    if (!slot) return
    slot.textContent = message
    slot.hidden = false
  }

  clearError(button) {
    const slot = this.errorSlot(button)
    if (slot) slot.hidden = true
  }

  // A neutral success note (its copy lives in the markup; we only toggle visibility), cleared by the next toggle.
  noteSlot(button) {
    return button.closest("[data-my-requests-card]")?.querySelector("[data-my-requests-card-note]")
  }

  showNote(button) {
    const slot = this.noteSlot(button)
    if (slot) slot.hidden = false
  }

  clearNote(button) {
    const slot = this.noteSlot(button)
    if (slot) slot.hidden = true
  }
}
