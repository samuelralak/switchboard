import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"
import { uploadImage, ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES } from "nostr/blossom"

// The non-custodial profile editor: collect the kind-0 fields, sign + broadcast them with the user's key
// (the browser does the signing; nothing is POSTed to Rails), then ping the server to fetch the new event
// back so the projection catches up. Optimistically updates the top-bar identity menu so the change shows
// immediately. Avatar/banner reuse the Blossom (NIP-B7) upload directly.
export default class extends Controller {
  static values = { pubkey: String, relays: Array, base: Object, refreshUrl: String }
  static targets = [
    "field", "status", "submit", "uploadStatus",
    "avatarPreview", "avatarPlaceholder", "avatarFile",
    "bannerPreview", "bannerPlaceholder", "bannerFile",
  ]

  async publish(event) {
    event.preventDefault()
    if (this.publishing) return
    this.publishing = true
    this.setBusy(true)
    this.setStatus("Publishing…", false)

    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) return this.fail("Connect or unlock your signer to publish.")

      const { broadcastProfile } = await import("nostr/profile_publish")
      const result = await broadcastProfile(this.collect(), this.baseValue, signer, this.relaysValue)
      if (result.reached === 0) throw new Error("Couldn't reach any relay. Try again.")

      this.succeed(result.reached)
      this.reflectIdentity()
      this.requestRefresh()
    } catch (error) {
      this.fail(error.message || "Couldn't publish your profile.")
    } finally {
      this.publishing = false
      this.setBusy(false)
    }
  }

  // Read every field by its data-field key (not its input name), so simple_form's name nesting is irrelevant.
  collect() {
    const data = {}
    this.fieldTargets.forEach((el) => { data[el.dataset.field] = el.value })
    return data
  }

  // --- avatar / banner upload (Blossom) ---

  pickAvatar() { this.avatarFileTarget.click() }
  pickBanner() { this.bannerFileTarget.click() }

  avatarSelected(event) { this.upload(event.currentTarget, "picture", this.uploadStatusTarget) }
  bannerSelected(event) { this.upload(event.currentTarget, "banner", this.uploadStatusTarget) }

  async upload(input, fieldName, statusEl) {
    const file = input.files?.[0]
    input.value = "" // let the same file be re-picked
    if (!file) return
    const problem = this.validateImage(file)
    if (problem) return this.setUploadStatus(statusEl, problem, true)

    this.setUploadStatus(statusEl, "Uploading…")
    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) return this.setUploadStatus(statusEl, "Unlock your signer to upload.", true)

      const meta = await uploadImage(file, signer)
      const field = this.fieldFor(fieldName)
      if (field) field.value = meta.url || ""
      if (fieldName === "picture") this.showAvatar(meta.url)
      else this.showBanner(meta.url)
      this.setUploadStatus(statusEl, "Uploaded.")
    } catch (error) {
      this.setUploadStatus(statusEl, error.message || "Upload failed.", true)
    }
  }

  validateImage(file) {
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) return "Use a PNG, JPEG, WebP, or GIF."
    if (file.size > MAX_IMAGE_BYTES) return "Image is too large (max 20 MiB)."
    return null
  }

  showAvatar(url) { this.togglePreview(this.avatarPreviewTarget, this.avatarPlaceholderTarget, url) }
  showBanner(url) { this.togglePreview(this.bannerPreviewTarget, this.bannerPlaceholderTarget, url) }

  // The preview img + placeholder use the Tailwind `hidden` CLASS (set at render from the prefill), so toggle
  // the class, not the `hidden` attribute.
  togglePreview(preview, placeholder, url) {
    const has = Boolean(url)
    if (has) preview.src = url
    preview.classList.toggle("hidden", !has)
    placeholder.classList.toggle("hidden", has)
  }

  // --- projection refresh + optimistic identity update ---

  // Ask the server to reconcile (PATCH the profile resource): fetch the just-broadcast kind-0 back,
  // force-bypassing the login cooldown. Best-effort -- the DB also catches up on the next login fetch.
  requestRefresh() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.refreshUrlValue, {
      method: "PATCH",
      headers: { "X-CSRF-Token": token || "", Accept: "application/json" },
    }).catch(() => {})
  }

  // Reflect the new avatar + name in the top-bar identity menu now, so the change is visible before the DB
  // projection lands. Only updates elements that already exist (an identicon-only avatar waits for reload).
  reflectIdentity() {
    const data = this.collect()
    const name = (data.display_name || data.name || "").trim()
    const picture = (data.picture || "").trim()
    if (picture) document.querySelectorAll("[data-identity-avatar]").forEach((img) => { img.src = picture })
    if (name) document.querySelectorAll("[data-identity-name]").forEach((el) => { el.textContent = name })
  }

  // --- status helpers ---

  succeed(reached) {
    this.setStatus(`Published to ${reached} relay${reached === 1 ? "" : "s"}. It appears across the app once a relay serves it back.`, false)
  }

  fail(message) {
    this.setStatus(message, true)
  }

  setStatus(message, isError) {
    if (!this.hasStatusTarget) return
    const el = this.statusTarget
    el.textContent = message
    el.hidden = false
    el.classList.toggle("border-lamp-fault/40", isError)
    el.classList.toggle("bg-lamp-fault/5", isError)
    el.classList.toggle("border-border", !isError)
    el.classList.toggle("bg-surface-2", !isError)
    el.classList.add("text-ink-secondary")
  }

  setUploadStatus(el, message, isError = false) {
    if (!el) return
    el.textContent = message
    el.classList.toggle("text-lamp-fault", isError)
    el.classList.toggle("text-ink-faint", !isError)
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = busy
  }

  fieldFor(name) {
    return this.fieldTargets.find((el) => el.dataset.field === name)
  }
}
