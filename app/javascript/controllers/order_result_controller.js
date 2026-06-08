import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor, lostNsecSession } from "nostr/signer_store"
import { canMessage } from "nostr/dm_client"
import { sendResultEnvelope, latestResultEnvelope } from "nostr/result_envelope"

// Two roles on the order page, one controller:
//  - CONSUMER (result panel): decrypt the provider's delivered result with the consumer's signer and render
//    it client-side. Trusted only when the envelope author === the order's provider. Runtime never sees it.
//  - PROVIDER (deliver panel): seal the finished result to the consumer over NIP-17, then record the
//    observable delivery assertion server-side (slice 4 wires deliverUrl). Keys/result stay in the browser.
// Content is written with textContent only: decrypted + provider-authored input must never become HTML.
const sentKey = (orderId) => `switchboard.order-result.${orderId}`

export default class extends Controller {
  static values = {
    orderId: String, coordinate: String, own: String, peer: String, provider: String,
    relays: Array, deliverUrl: String,
  }
  static targets = [ "result", "status", "unlock", "form", "field", "note", "attachments", "submit", "error" ]

  connect() {
    this.active = true // cleared by disconnect(); guards async work against a navigate-away race
    if (this.hasResultTarget) this.connectConsumer()
    if (this.hasFormTarget && this.alreadySent()) this.showSent()
  }

  disconnect() {
    this.active = false
  }

  // --- consumer: decrypt + render the delivered result ---

  async connectConsumer() {
    let signer
    try {
      signer = await ensureSignerFor(this.ownValue, { prompt: false }) // passive load never auto-prompts
    } catch (error) {
      return this.setStatus(error.message)
    }
    if (!signer) return this.showLocked()
    await this.hydrate(signer)
  }

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
    this.setStatus("Decrypting the delivered result…")
    try {
      if (!(await canMessage(signer))) return this.setStatus("This signer can't decrypt the result (NIP-44 unavailable).")
      const result = await latestResultEnvelope({
        signer, ownPubkey: this.ownValue, relays: this.relaysValue,
        orderId: this.orderIdValue, provider: this.providerValue,
      })
      if (!this.active) return // navigated away mid-fetch
      if (!result) return this.setStatus("No result delivered yet.")
      this.render(result)
    } catch {
      this.setStatus("Couldn't reach your relays to load the result.")
    }
  }

  render(result) {
    this.resultTarget.replaceChildren()
    if (result.result) this.resultTarget.append(this.body(result.result))
    const links = (result.attachments || []).map((a) => this.attachment(a)).filter(Boolean)
    if (links.length) this.resultTarget.append(this.attachmentList(links))
    this.setStatus(result.result || links.length ? "" : "The provider delivered an empty result.")
  }

  body(text) {
    const p = document.createElement("p")
    p.className = "text-sm leading-relaxed whitespace-pre-wrap break-words text-ink-secondary"
    p.textContent = text // plain text; markdown rendering is a later enhancement, never raw innerHTML
    return p
  }

  attachmentList(links) {
    const wrap = document.createElement("div")
    wrap.className = "mt-4 border-t border-border pt-4 flex flex-col gap-2"
    const label = document.createElement("p")
    label.className = "text-xs font-medium uppercase tracking-wider text-ink-muted"
    label.textContent = "attachments"
    wrap.append(label, ...links)
    return wrap
  }

  // An attachment reference (url + content hash). Only http(s) URLs become links; anything else is inert
  // text so a hostile scheme (javascript:) can never be clicked.
  attachment(att) {
    if (!att || typeof att.url !== "string") return null
    const row = document.createElement("div")
    row.className = "flex items-baseline justify-between gap-3 text-sm"
    const left = document.createElement("span")
    left.className = "min-w-0 truncate"
    if (/^https?:\/\//i.test(att.url)) {
      const a = document.createElement("a")
      a.href = att.url
      a.target = "_blank"
      a.rel = "noopener noreferrer"
      a.className = "text-copper hover:text-copper-bright break-all"
      a.textContent = att.name || att.url
      left.append(a)
    } else {
      left.textContent = att.name || att.url
    }
    const hash = document.createElement("span")
    hash.className = "shrink-0 font-mono text-xs text-ink-faint"
    hash.textContent = att.hash ? `sha256 ${String(att.hash).slice(0, 12)}` : ""
    row.append(left, hash)
    return row
  }

  showLocked() {
    if (lostNsecSession(this.ownValue)) {
      return this.setStatus("Your key was cleared on reload. Sign in again to read the delivered result.")
    }
    this.setStatus("Unlock your signer to read the delivered result.")
    if (this.hasUnlockTarget) this.unlockTarget.classList.remove("hidden")
  }

  hideUnlock() {
    if (this.hasUnlockTarget) this.unlockTarget.classList.add("hidden")
  }

  // --- provider: seal the result to the consumer (+ record the delivery assertion, slice 4) ---

  async send(event) {
    event?.preventDefault() // the simple_form <form> submits to "#"; the result goes out over NIP-17, not HTTP
    this.clearError()
    const result = this.hasFieldTarget ? this.fieldTarget.value.trim() : ""
    const note = this.hasNoteTarget ? this.noteTarget.value.trim() : ""
    const attachments = this.collectAttachments()
    if (!result && !attachments.length) return this.showError("Add the result or an attachment before delivering.")

    this.submitTarget.disabled = true
    this.setStatus("Encrypting and delivering…")
    try {
      const signer = await ensureSignerFor(this.ownValue, { prompt: true })
      if (!signer) throw new Error("Unlock your signer to deliver the result.")
      const sent = await sendResultEnvelope({
        signer, ownPubkey: this.ownValue, peerPubkey: this.peerValue, relays: this.relaysValue,
        orderId: this.orderIdValue, coordinate: this.coordinateValue, result, attachments, note,
      })
      await this.recordDelivery(sent, result, attachments) // slice 4: observable assertion; no-op without deliverUrl
      this.markSent()
      this.showSent()
    } catch (error) {
      this.submitTarget.disabled = false
      this.setStatus("")
      this.showError(error?.message || "Couldn't deliver the result. Please try again.")
    }
  }

  // Parse the attachment-reference rows the provider added: a url (+ optional name). The content hash is
  // computed here so the server-recorded commitment matches what was sealed.
  collectAttachments() {
    if (!this.hasAttachmentsTarget) return []
    return this.attachmentsTarget.value
      .split("\n").map((line) => line.trim()).filter((line) => /^https?:\/\//i.test(line))
      .map((url) => ({ url }))
  }

  // Slice 4 wires deliverUrl to POST the observable assertion { delivery_event_id, delivered_at,
  // content_hash }. Until then this is a no-op so the E2E result flow ships independently (Option B).
  async recordDelivery(sent, result, attachments) {
    if (!this.hasDeliverUrlValue || !this.deliverUrlValue) return
    const contentHash = await sha256Hex(JSON.stringify({ result, attachments }))
    const token = document.querySelector("meta[name='csrf-token']")?.content
    await fetch(this.deliverUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify({ delivery: { delivery_event_id: sent.id, delivered_at: sent.created_at, content_hash: contentHash } }),
    })
  }

  showSent() {
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    this.setStatus("Result delivered to the client.")
  }

  alreadySent() {
    try { return sessionStorage.getItem(sentKey(this.orderIdValue)) === "1" } catch { return false }
  }

  markSent() {
    try { sessionStorage.setItem(sentKey(this.orderIdValue), "1") } catch { /* private mode: re-deliver is harmless */ }
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

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("")
}
