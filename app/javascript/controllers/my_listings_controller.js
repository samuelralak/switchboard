import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// Studio My-listings: unpublish (status -> inactive) / re-publish (status -> active) by re-signing the
// existing listing event with the status tag flipped (preserving all data, reversible) and broadcasting
// it with the provider's key (identity-gated). The card flips in place; the catalog catches up once a
// relay serves the new version back. Edit is a plain link to the prefilled form.
export default class extends Controller {
  static values = { pubkey: String, relays: Array, marker: String, capabilityNamespace: String, origin: String }

  async toggleStatus(event) {
    const button = event.currentTarget
    const status = event.params.status // the status to apply
    const original = button.textContent
    button.disabled = true
    button.textContent = status === "inactive" ? "Unpublishing…" : "Re-publishing…"
    this.clearError(button)
    this.clearNote(button)

    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) return this.fail(button, original, "Connect or unlock your signer.")

      const { setListingStatus } = await import("nostr/listing_publish")
      const config = { marker: this.markerValue, capabilityNamespace: this.capabilityNamespaceValue, origin: this.originValue }
      const result = await setListingStatus(event.params.payload, status, config, signer, this.relaysValue)
      if (result.reached === 0) throw new Error("Couldn't reach any relay. Try again.")
      this.applyStatus(button, status, result.event)
    } catch (error) {
      this.fail(button, original, error.message)
    }
  }

  // Flip the card's status badge + the button in place (the next toggle reverses it), and refresh the
  // payload to the just-published version so a second toggle re-signs from it (monotonic created_at).
  applyStatus(button, appliedStatus, signedEvent) {
    const nowActive = appliedStatus === "active"
    const badge = button.closest("[data-my-listings-card]")?.querySelector('[data-role="status"]')
    if (badge) {
      badge.textContent = appliedStatus
      badge.classList.toggle("text-lamp-settled", nowActive)
      badge.classList.toggle("text-ink-faint", !nowActive)
    }
    button.disabled = false
    button.dataset.myListingsStatusParam = nowActive ? "inactive" : "active"
    button.textContent = nowActive ? "Unpublish" : "Re-publish"
    if (signedEvent) {
      button.dataset.myListingsPayloadParam = JSON.stringify({
        kind: signedEvent.kind, content: signedEvent.content, tags: signedEvent.tags, created_at: signedEvent.created_at,
      })
    }
    this.showNote(button) // reached >= 1 (reached === 0 threw before here): honest catalog-lag note
  }

  fail(button, original, message) {
    button.disabled = false
    button.textContent = original
    this.showError(button, message)
  }

  // The error belongs to the card whose toggle failed, so other cards stay quiet.
  errorSlot(button) {
    return button.closest("[data-my-listings-card]")?.querySelector("[data-my-listings-card-error]")
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
    return button.closest("[data-my-listings-card]")?.querySelector("[data-my-listings-card-note]")
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
