import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor, lostNsecSession } from "nostr/signer_store"
import { canMessage } from "nostr/dm_client"
import { latestOrderRequest } from "nostr/order_envelope"

// Provider-side hydration for the order ledger thread. The server renders the order metadata; the request
// CONTENT (the filled schema + the client's note) is end-to-end encrypted, so it is decrypted HERE with the
// provider's signer and rendered client-side. Rails never sees it. A decrypted envelope is trusted only
// when its author matches the order's known consumer (consumerValue) -- anyone can gift-wrap the provider.
// Content is written with textContent only: it is untrusted client input and must never become HTML.
export default class extends Controller {
  static values = { own: String, relays: Array, orderId: String, consumer: String }
  static targets = [ "request", "status", "unlock" ]

  async connect() {
    this.active = true // cleared by disconnect(); guards the async hydrate against a navigate-away race
    let signer
    try {
      signer = await ensureSignerFor(this.ownValue, { prompt: false }) // a passive load never auto-prompts
    } catch (error) {
      return this.setStatus(error.message) // identity mismatch on a live signer
    }
    if (!signer) return this.showLocked()
    await this.hydrate(signer)
  }

  // The unlock button is a real user gesture, so prompting the nsec passphrase / a re-acquire is allowed.
  async unlock() {
    let signer
    try {
      signer = await ensureSignerFor(this.ownValue, { prompt: true })
    } catch (error) {
      return this.setStatus(error.message)
    }
    if (!signer) return
    this.hideUnlock()
    await this.hydrate(signer)
  }

  async hydrate(signer) {
    this.setStatus("Decrypting the client's request…")
    try {
      if (!(await canMessage(signer))) return this.setStatus("This signer can't decrypt the request (NIP-44 unavailable).")
      const request = await latestOrderRequest({
        signer, ownPubkey: this.ownValue, relays: this.relaysValue,
        orderId: this.orderIdValue, consumer: this.consumerValue,
      })
      if (!this.active) return // navigated away mid-fetch
      if (!request) return this.setStatus("No request from the client yet.")
      this.render(request)
    } catch {
      this.setStatus("Couldn't reach your relays to load the request.")
    }
  }

  render(request) {
    if (!this.hasRequestTarget) return
    this.requestTarget.replaceChildren()
    if (request.inputs.length) this.requestTarget.append(this.inputList(request.inputs))
    if (request.note) this.requestTarget.append(this.noteBlock(request.note))
    this.setStatus(request.inputs.length || request.note ? "" : "The client sent an empty request.")
  }

  inputList(inputs) {
    const list = document.createElement("dl")
    list.className = "-mb-3 divide-y divide-border"
    for (const input of inputs) {
      const row = document.createElement("div")
      row.className = "py-3"
      const term = document.createElement("dt")
      term.className = "mb-1 text-xs font-medium text-ink-muted"
      term.textContent = input.label || "—"
      const value = document.createElement("dd")
      value.className = "text-sm whitespace-pre-wrap break-words text-ink"
      value.textContent = input.value || ""
      row.append(term, value)
      list.append(row)
    }
    return list
  }

  noteBlock(note) {
    const wrap = document.createElement("div")
    wrap.className = "mt-4 border-t border-border pt-4"
    const label = document.createElement("p")
    label.className = "mb-1 text-xs font-medium uppercase tracking-wider text-ink-muted"
    label.textContent = "note from the client"
    const body = document.createElement("p")
    body.className = "text-sm leading-relaxed whitespace-pre-wrap break-words text-ink-secondary"
    body.textContent = note
    wrap.append(label, body)
    return wrap
  }

  showLocked() {
    if (lostNsecSession(this.ownValue)) {
      return this.setStatus("Your key was cleared on reload. Sign in again to read the client's request.")
    }
    this.setStatus("Unlock your signer to read the client's request.")
    if (this.hasUnlockTarget) this.unlockTarget.classList.remove("hidden")
  }

  hideUnlock() {
    if (this.hasUnlockTarget) this.unlockTarget.classList.add("hidden")
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  disconnect() {
    this.active = false
  }
}
