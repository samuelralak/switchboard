import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor, savedMethod, needsUnlock, lostNsecSession } from "nostr/signer_store"

// Provider studio authoring: the schema-row repeater, the fulfillment-mode toggle, the live fiat hint,
// the section rail (scroll-spy + per-section progress), the on-demand buyer preview, strict client-side
// validation, and the non-custodial publish (sign the kind-30402 listing + kind-31990 handler with the
// provider's key, then broadcast). The wire format is built by nostr/listing_publish.
//
// The buyer preview is on-demand: "Preview as buyer" submits the form to studio#preview, which returns
// the real ServiceDetailComponent into the turbo frame inside the preview drawer (opened natively).
export default class extends Controller {
  static targets = [
    "form", "composer", "rows", "rowsEmpty", "rowTemplate",
    "modeInput", "modeButton", "modeManual",
    "navItem", "section", "priceHint", "priceFrequency", "priceBasisButton", "priceUnit",
    "previewFrame", "previewPaused",
    "errors", "publish", "receipt", "receiptDetail", "receiptCoordinate"
  ]
  // pubkey: the signed-in account the publisher signs as (identity-gated); marker / capabilityNamespace
  // / origin: the server-pinned wire-format constants; relays: where the listing is broadcast; btcUsd:
  // the cached BTC/USD rate for the fiat hint (0 = unavailable -> hint hidden).
  static values = { pubkey: String, marker: String, capabilityNamespace: String, origin: String, relays: Array, btcUsd: Number }

  connect() {
    this.renderFiatHint()
    this.refreshProgress()
    this.setupScrollSpy()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // Anything the provider edits refreshes the fiat hint and the rail's per-section progress.
  formChanged() {
    this.renderFiatHint()
    this.refreshProgress()
  }

  // Schema rows
  addField() {
    const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
    this.rowsTarget.appendChild(row)
    this.syncRowsChrome()
    row.querySelector('[data-studio-target="rowLabel"]')?.focus()
  }

  removeField(event) {
    event.target.closest('[data-studio-target="row"]')?.remove()
    this.syncRowsChrome()
  }

  // Hide the empty hint only while rows exist.
  syncRowsChrome() {
    if (this.hasRowsEmptyTarget) this.rowsEmptyTarget.hidden = this.rowsTarget.children.length !== 0
  }

  // Auto-fill the machine name from the label (snake_case), unless the provider has edited it.
  slugName(event) {
    const label = event.target
    const nameInput = label.closest('[data-studio-target="row"]')?.querySelector('[data-studio-target="rowName"]')
    if (!nameInput) return
    if (nameInput.value !== "" && nameInput.dataset.autoslug !== "true") return

    nameInput.value = this.slugify(label.value)
    nameInput.dataset.autoslug = "true"
  }

  // Once the provider types in the name field, stop auto-deriving it (overridable per the schema spec).
  nameEdited(event) {
    delete event.target.dataset.autoslug
  }

  slugify(text) {
    return text.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "field"
  }

  // Fulfillment mode
  // Manual is the only selectable mode for now (automated is coming-soon, rendered as a disabled card).
  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    this.modeInputTarget.value = mode
    this.modeButtonTargets.forEach((btn) => btn.setAttribute("aria-pressed", String(btn.dataset.mode === mode)))
    if (this.hasModeManualTarget) this.modeManualTarget.hidden = mode !== "manual"
    this.refreshProgress()
  }

  // Pricing basis
  setPriceBasis(event) {
    const hour = event.currentTarget.dataset.basis === "hour"
    if (this.hasPriceFrequencyTarget) this.priceFrequencyTarget.value = hour ? "hour" : "" // NIP-99 frequency
    this.priceBasisButtonTargets.forEach((btn) => btn.setAttribute("aria-pressed", String((btn.dataset.basis === "hour") === hour)))
    if (this.hasPriceUnitTarget) this.priceUnitTarget.textContent = hour ? "(sat / hr)" : "(sat)"
    this.renderFiatHint()
  }

  // Fiat hint
  renderFiatHint() {
    if (!this.hasPriceHintTarget) return
    const rate = this.btcUsdValue
    const sats = Number((this.field("price")?.value || "").trim())
    if (!rate || !Number.isFinite(sats) || sats <= 0) {
      this.priceHintTarget.textContent = ""
      return
    }
    const perHour = this.hasPriceFrequencyTarget && this.priceFrequencyTarget.value === "hour"
    this.priceHintTarget.textContent = `≈ ${this.formatUsd((sats / 1e8) * rate)} USD${perHour ? " / hr" : ""}`
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
    if (id === "details") return Boolean(v("title")) && Boolean(v("capability")) && this.isPositiveInt(v("price"))
    if (id === "delivery") return this.isPositiveInt(v("delivery_value"))
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
  // Strict gate before the non-custodial sign + broadcast. The publisher overrides publishListing().
  publish(event) {
    event.preventDefault()
    const errors = this.validate()
    if (errors.length) return this.showErrors(errors)

    this.clearErrors()
    this.publishListing()
  }

  // Non-custodial publish: resolve + identity-check the signer, then sign the kind-30402 listing +
  // kind-31990 handler announcement and broadcast them to the catalog relays.
  async publishListing() {
    this.setPublishing(true)

    let signer
    try {
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
    } catch (error) {
      return this.failPublish([ error.message ]) // mismatched key or unreachable remote signer
    }
    if (!signer) return this.failPublish([ this.noSignerMessage() ])

    try {
      const { broadcastListing } = await import("nostr/listing_publish")
      const result = await broadcastListing(this.collectData(), this.config(), signer, this.relaysValue)
      if (result.reached === 0) return this.failPublish([ "Couldn't reach any relay. Check your connection and try again." ])
      this.showReceipt(result, await this.enableEscrowReceiving(signer))
    } catch (error) {
      this.failPublish([ `Couldn't publish: ${error.message}` ])
    }
  }

  // Publish the provider's NIP-61 kind:10019 so consumers can discover the P2PK key to lock escrow to.
  // The listing publishes regardless; this returns whether the escrow key reached a relay so the receipt
  // can warn the provider (else buyers cannot fund). ensureEscrowIdentity is idempotent on a re-publish.
  async enableEscrowReceiving(signer) {
    try {
      const { ensureEscrowIdentity } = await import("nostr/escrow_identity")
      await ensureEscrowIdentity({ accountPubkey: this.pubkeyValue, signer, relays: this.relaysValue, mints: [] })
      return true
    } catch (error) {
      console.warn("escrow receiving not enabled:", error?.message)
      return false
    }
  }

  config() {
    return { marker: this.markerValue, capabilityNamespace: this.capabilityNamespaceValue, origin: this.originValue }
  }

  // Read the form into the shape nostr/listing_publish expects (delivery value+unit collapse to the
  // microstandard "24h"/"3d", schema rows + image cards become arrays).
  collectData() {
    const v = (name) => (this.field(name)?.value || "").trim()
    const window = v("delivery_value")
    const unit = v("delivery_unit") === "days" ? "d" : "h"
    return {
      dTag: v("d_tag"), // present on edit -> re-publish supersedes the same coordinate; empty -> mint a fresh id
      status: v("status"), // carried on edit so re-publish preserves visibility (default "active" for new)
      publishedAt: v("published_at"), // carried on edit so the original publish date survives
      createdAt: v("created_at"), // the prior event's created_at -> the publisher bumps past it (supersede)
      title: v("title"),
      description: v("description"),
      capability: v("capability"),
      price: v("price"),
      priceFrequency: v("price_frequency"), // "" (per request) or "hour" (per-hour rate)
      fulfillment: v("fulfillment"),
      endpoint: v("endpoint"),
      deliveryWindow: window ? `${window}${unit}` : "",
      schema: this.collectSchema(),
      images: this.collectImages(),
    }
  }

  collectSchema() {
    return Array.from(this.rowsTarget.children).flatMap((row) => {
      const label = (row.querySelector('[data-studio-target="rowLabel"]')?.value || "").trim()
      if (!label) return []
      const name = (row.querySelector('[data-studio-target="rowName"]')?.value || "").trim() || this.slugify(label)
      return [ { name, label, type: row.querySelector('select')?.value || "text", required: !!row.querySelector('input[type="checkbox"]')?.checked } ]
    })
  }

  collectImages() {
    return Array.from(this.element.querySelectorAll('[data-image-upload-target="item"]')).flatMap((item) => {
      const url = item.querySelector('[data-field="url"]')?.value || ""
      if (!url) return []
      return [ { url, m: item.querySelector('[data-field="m"]')?.value || "", x: item.querySelector('[data-field="x"]')?.value || "", dim: item.querySelector('[data-field="dim"]')?.value || "" } ]
    })
  }

  showReceipt(result, escrowEnabled = true) {
    if (this.hasComposerTarget) this.composerTarget.hidden = true
    if (this.hasReceiptDetailTarget) {
      const reach = `Broadcast to ${result.reached} of ${result.listingResults.length} relays. It appears in the catalog once a relay serves it back.`
      this.receiptDetailTarget.textContent = escrowEnabled ? reach
        : `${reach} Escrow payments couldn't be enabled (a relay was unreachable) — re-publish to enable them, or buyers can't fund orders.`
    }
    if (this.hasReceiptCoordinateTarget) this.receiptCoordinateTarget.textContent = result.coordinate
    if (this.hasReceiptTarget) {
      this.receiptTarget.hidden = false
      this.receiptTarget.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

  publishAnother() {
    Turbo.visit(window.location.href, { action: "replace" }) // reset the form for a fresh listing
  }

  setPublishing(on) {
    if (this.hasPublishTarget) {
      this.publishTarget.disabled = on
      this.publishTarget.textContent = on ? "Publishing…" : "Sign & publish listing"
    }
    if (on) this.clearErrors()
  }

  failPublish(errors) {
    this.setPublishing(false)
    this.showErrors(errors)
  }

  noSignerMessage() {
    if (savedMethod() === "nsec" && needsUnlock(this.pubkeyValue)) return "Unlock your key to publish."
    if (lostNsecSession(this.pubkeyValue)) return "Your key was cleared on reload. Sign in again to publish."
    if (savedMethod() === "nip07") return "Your Nostr extension isn't available. Unlock it, then retry."
    return "Connect or unlock your signer to publish."
  }

  // Returns a list of human-readable problems; empty means valid.
  validate() {
    const errors = []
    const v = (name) => (this.field(name)?.value || "").trim()

    if (!v("title")) errors.push("Add a service name.")
    if (!v("capability")) errors.push("Add a capability tag.")
    if (!this.isPositiveInt(v("price"))) errors.push("Set a price in sats (a whole number above zero).")

    const mode = v("fulfillment")
    if (mode === "automated" && !this.isUrl(v("endpoint"))) errors.push("Add a valid endpoint URL for automated fulfillment.")
    if (mode === "manual" && !this.isPositiveInt(v("delivery_value"))) errors.push("Set a delivery window for manual fulfillment.")

    // A fully-blank row is ignored (collectSchema drops it); only a row with content but no label errors.
    this.rowsTarget.querySelectorAll('[data-studio-target="row"]').forEach((row) => {
      const label = row.querySelector('[data-studio-target="rowLabel"]')?.value.trim()
      const name = row.querySelector('[data-studio-target="rowName"]')?.value.trim()
      const type = row.querySelector("select")?.value
      if (!label && (name || (type && type !== "text"))) errors.push("Every input-schema field needs a label.")
    })
    return [ ...new Set(errors) ]
  }

  field(name) {
    return this.formTarget.querySelector(`[name="${name}"]`)
  }

  isPositiveInt(value) {
    return /^\d+$/.test(value) && Number(value) > 0
  }

  isUrl(value) {
    try {
      const url = new URL(value)
      return url.protocol === "http:" || url.protocol === "https:"
    } catch {
      return false
    }
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
