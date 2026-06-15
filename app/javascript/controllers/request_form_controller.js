import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor, savedMethod, needsUnlock, lostNsecSession } from "nostr/signer_store"

// Open-request authoring: the live fiat hint, the section rail (scroll-spy + per-section progress), the
// on-demand preview, strict client-side validation, and the non-custodial publish (sign the kind-30402
// request with the consumer's key, then broadcast). The wire format is built by nostr/request_publish.
// The demand-side mirror of the studio controller, trimmed: no schema rows, no fulfillment mode, no
// price-basis toggle (a request is always manual with one fixed budget).
//
// The preview is on-demand: "Preview" submits the form to requests#preview, which returns the real
// RequestDetailComponent into the turbo frame inside the preview drawer (opened natively).
export default class extends Controller {
  static targets = [
    "form", "composer", "navItem", "section", "priceHint",
    "previewFrame", "previewPaused",
    "errors", "publish", "receipt", "receiptDetail", "receiptCoordinate"
  ]
  // pubkey: the signed-in account the publisher signs as (identity-gated); marker / capabilityNamespace:
  // the server-pinned wire-format constants; relays: where the request is broadcast; btcUsd: the cached
  // BTC/USD rate for the fiat hint (0 = unavailable -> hint hidden).
  static values = { pubkey: String, marker: String, capabilityNamespace: String, relays: Array, btcUsd: Number }

  connect() {
    this.renderFiatHint()
    this.refreshProgress()
    this.setupScrollSpy()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // Anything the consumer edits refreshes the fiat hint and the rail's per-section progress.
  formChanged() {
    this.renderFiatHint()
    this.refreshProgress()
  }

  // Fiat hint
  renderFiatHint() {
    if (!this.hasPriceHintTarget) return
    const rate = this.btcUsdValue
    const sats = Number((this.field("budget")?.value || "").trim())
    if (!rate || !Number.isFinite(sats) || sats <= 0) {
      this.priceHintTarget.textContent = ""
      return
    }
    this.priceHintTarget.textContent = `≈ ${this.formatUsd((sats / 1e8) * rate)} USD`
  }

  formatUsd(usd) {
    if (usd >= 1) return `$${usd.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
    if (usd >= 0.01) return `$${usd.toFixed(2)}`
    return `$${usd.toFixed(4)}`
  }

  // Section rail
  setupScrollSpy() {
    if (!this.hasSectionTarget || typeof IntersectionObserver === "undefined") return
    // The active section is the topmost one crossing a band near the top of the viewport.
    this.observer = new IntersectionObserver((entries) => {
      const visible = entries.filter((entry) => entry.isIntersecting)
      if (!visible.length) return
      const top = visible.sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0]
      this.setActive(top.target.dataset.section)
    }, { rootMargin: "-20% 0px -70% 0px", threshold: 0 })
    this.sectionTargets.forEach((section) => this.observer.observe(section))
  }

  navClick(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.section
    this.sectionTargets.find((section) => section.dataset.section === id)?.scrollIntoView({ behavior: "smooth", block: "start" })
    this.setActive(id)
  }

  setActive(id) {
    if (!this.hasNavItemTarget) return
    this.navItemTargets.forEach((item) => item.setAttribute("aria-current", String(item.dataset.section === id)))
  }

  // Fill a required section's rail dot once its required fields are satisfied.
  refreshProgress() {
    if (!this.hasNavItemTarget) return
    this.navItemTargets.forEach((item) => {
      if (item.dataset.required !== "true") return
      const done = this.sectionComplete(item.dataset.section)
      const dot = item.querySelector('[data-role="dot"]')
      if (!dot) return
      dot.classList.toggle("bg-copper", done)
      dot.classList.toggle("border-copper", done)
      dot.classList.toggle("border-border-strong", !done)
    })
  }

  sectionComplete(id) {
    const v = (name) => (this.field(name)?.value || "").trim()
    if (id === "details") return Boolean(v("title")) && Boolean(v("capability"))
    if (id === "budget") return this.isPositiveInt(v("budget"))
    if (id === "timing") return this.isPositiveInt(v("claim_value")) && this.isPositiveInt(v("delivery_value"))
    return true
  }

  // Preview
  // The drawer opens natively (command="show-modal"); we just submit the form into its frame.
  previewAsBuyer() {
    if (this.hasFormTarget) this.formTarget.requestSubmit()
  }

  // A failed preview render leaves stale content in the frame. Dim it and surface a quiet "paused" note
  // instead of blanking or navigating away (preventDefault stops Turbo's full-page fallback on frame-missing).
  previewFailed(event) {
    event.preventDefault()
    if (this.hasPreviewPausedTarget) this.previewPausedTarget.hidden = false
    if (this.hasPreviewFrameTarget) this.previewFrameTarget.classList.add("opacity-40")
  }

  previewLoaded() {
    if (this.hasPreviewPausedTarget) this.previewPausedTarget.hidden = true
    if (this.hasPreviewFrameTarget) this.previewFrameTarget.classList.remove("opacity-40")
  }

  // Publish
  // Strict gate before the non-custodial sign + broadcast.
  publish(event) {
    event.preventDefault()
    const errors = this.validate()
    if (errors.length) return this.showErrors(errors)

    this.clearErrors()
    this.publishRequest()
  }

  // Non-custodial publish: resolve + identity-check the signer, then sign the kind-30402 request and
  // broadcast it to the catalog relays.
  async publishRequest() {
    this.setPublishing(true)

    let signer
    try {
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
    } catch (error) {
      return this.failPublish([ error.message ]) // mismatched key or unreachable remote signer
    }
    if (!signer) return this.failPublish([ this.noSignerMessage() ])

    try {
      const { broadcastRequest } = await import("nostr/request_publish")
      const result = await broadcastRequest(this.collectData(), this.config(), signer, this.relaysValue)
      if (result.reached === 0) return this.failPublish([ "Couldn't reach any relay. Check your connection and try again." ])
      this.showReceipt(result)

      const { reportForAttestation } = await import("nostr/attestation_report")
      reportForAttestation(result.event) // best-effort: ask the platform to attest our published request
    } catch (error) {
      this.failPublish([ `Couldn't publish: ${error.message}` ])
    }
  }

  config() {
    return { marker: this.markerValue, capabilityNamespace: this.capabilityNamespaceValue }
  }

  // Read the form into the shape nostr/request_publish expects (each window's value+unit collapses to the
  // microstandard "24h"/"3d").
  collectData() {
    const v = (name) => (this.field(name)?.value || "").trim()
    const deliveryValue = v("delivery_value")
    const claimValue = v("claim_value")
    return {
      dTag: v("d_tag"), // present on edit -> re-publish supersedes the same coordinate; empty -> mint a fresh id
      status: v("status"), // carried on edit (default "active" for new)
      publishedAt: v("published_at"), // carried on edit so the original post date survives
      createdAt: v("created_at"), // the prior event's created_at -> the publisher bumps past it (supersede)
      title: v("title"),
      description: v("description"),
      capability: v("capability"),
      budget: v("budget"),
      deliveryWindow: deliveryValue ? `${deliveryValue}${v("delivery_unit") === "days" ? "d" : "h"}` : "",
      claimWindow: claimValue ? `${claimValue}${v("claim_unit") === "hours" ? "h" : "d"}` : "",
      escrowTier: this.selectedTier()?.value || "", // empty when the arbiter isn't offered -> publishes as tier-1
      images: this.collectImages(),
    }
  }

  // The checked escrow-tier radio, or null when the Funding section offers no choice (arbiter unprovisioned).
  selectedTier() {
    return this.formTarget.querySelector('[name="escrow_tier"]:checked')
  }

  // Read the image picker's cards (rendered by the nested image-upload controller, inside this root) into
  // the { url, m, x, dim } shape request_publish expects; the first card is the cover.
  collectImages() {
    return Array.from(this.element.querySelectorAll('[data-image-upload-target="item"]')).flatMap((item) => {
      const url = item.querySelector('[data-field="url"]')?.value || ""
      if (!url) return []
      return [ { url, m: item.querySelector('[data-field="m"]')?.value || "", x: item.querySelector('[data-field="x"]')?.value || "", dim: item.querySelector('[data-field="dim"]')?.value || "" } ]
    })
  }

  showReceipt(result) {
    if (this.hasComposerTarget) this.composerTarget.hidden = true
    if (this.hasReceiptDetailTarget) {
      this.receiptDetailTarget.textContent =
        `Broadcast to ${result.reached} of ${result.results.length} relays. It appears in the catalog and your requests once a relay serves it back.`
    }
    if (this.hasReceiptCoordinateTarget) this.receiptCoordinateTarget.textContent = result.coordinate
    if (this.hasReceiptTarget) {
      this.receiptTarget.hidden = false
      this.receiptTarget.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

  publishAnother() {
    Turbo.visit(window.location.href, { action: "replace" }) // reset the form for a fresh request
  }

  setPublishing(on) {
    if (this.hasPublishTarget) {
      this.publishTarget.disabled = on
      this.publishTarget.textContent = on ? "Posting…" : "Sign & post request"
    }
    if (on) this.clearErrors()
  }

  failPublish(errors) {
    this.setPublishing(false)
    this.showErrors(errors)
  }

  noSignerMessage() {
    if (savedMethod() === "nsec" && needsUnlock(this.pubkeyValue)) return "Unlock your key to post."
    if (lostNsecSession(this.pubkeyValue)) return "Your key was cleared on reload. Sign in again to post."
    if (savedMethod() === "nip07") return "Your Nostr extension isn't available. Unlock it, then retry."
    return "Connect or unlock your signer to post."
  }

  // Returns a list of human-readable problems; empty means valid.
  validate() {
    const errors = []
    const v = (name) => (this.field(name)?.value || "").trim()

    if (!v("title")) errors.push("Add a title for your request.")
    if (!v("capability")) errors.push("Add a capability tag.")
    if (!this.isPositiveInt(v("budget"))) errors.push("Set a budget in sats (a whole number above zero).")
    if (!this.isPositiveInt(v("claim_value"))) errors.push("Set a claim window.")
    if (!this.isPositiveInt(v("delivery_value"))) errors.push("Set a delivery window.")

    // Mediated escrow carries a lower per-order cap; a budget above it would publish an unclaimable request
    // (Orders::Create rejects the claim). Block it here. cap lives on the tier-2 radio (data-cap).
    const cap = Number(this.selectedTier()?.dataset.cap)
    if (cap > 0 && Number(v("budget")) > cap) {
      errors.push(`Mediated escrow is limited to ${cap.toLocaleString("en-US")} sat. Lower the budget or choose standard escrow.`)
    }

    return [ ...new Set(errors) ]
  }

  field(name) {
    return this.formTarget.querySelector(`[name="${name}"]`)
  }

  isPositiveInt(value) {
    return /^\d+$/.test(value) && Number(value) > 0
  }

  showErrors(errors) {
    if (!this.hasErrorsTarget) return
    this.errorsTarget.innerHTML = ""
    const list = document.createElement("ul")
    list.className = "list-disc space-y-1 pl-5"
    errors.forEach((message) => {
      const item = document.createElement("li")
      item.textContent = message
      list.appendChild(item)
    })
    this.errorsTarget.appendChild(list)
    this.errorsTarget.hidden = false
    this.errorsTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  clearErrors() {
    if (!this.hasErrorsTarget) return
    this.errorsTarget.hidden = true
    this.errorsTarget.innerHTML = ""
  }
}
