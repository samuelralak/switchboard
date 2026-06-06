import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor, savedMethod, needsUnlock, lostNsecSession } from "nostr/signer_store"
import { uploadImage, ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES } from "nostr/blossom"

// Provider-studio image picker: non-custodial Blossom (NIP-B7) uploads. Each image is authorized by a
// kind-24242 event the user's signer signs (taken from the tab registry and checked against the
// signed-in account's pubkey); the blob is stored content-addressed on blossom.band and carried on the
// listing as an https URL + NIP-92 imeta (url/m/x/dim). Up to MAX images, first = cover. Each thumbnail
// owns its hidden inputs, so the picker state IS the form state. Emits image-upload:changed to refresh.
const MAX = 5

// Each card's source File, so an errored upload can be retried without re-selecting. Keyed by the item
// element; a removed card's File is reclaimed automatically (it never leaks into the DOM or a global).
const files = new WeakMap()

export default class extends Controller {
  static targets = ["input", "grid", "template", "empty", "add", "error"]
  static values = { pubkey: String }

  connect() {
    this.syncChrome()
  }

  open() {
    if (!this.full()) this.inputTarget.click()
  }

  selected(event) {
    const picked = Array.from(event.target.files || []) // not `files`: that is the module-level retry WeakMap
    event.target.value = "" // let the same file be re-picked after a remove
    // Enforce the cap synchronously here: addFile appends asynchronously (it awaits the signer), so a
    // per-file full() check would let a multi-select slip past the limit. Budget the room up front.
    let room = MAX - this.liveCount()
    for (const file of picked) {
      if (room <= 0) { this.showError(`You can add up to ${MAX} images.`); break }
      room -= 1
      this.addFile(file)
    }
  }

  async addFile(file) {
    const problem = this.validate(file)
    if (problem) return this.showError(problem)
    this.clearError()

    // Resolve + identity-check the signer first (re-hydrating / prompting to unlock as needed) so we
    // don't show an uploading thumbnail while waiting on a passphrase.
    let signer
    try {
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
    } catch (error) {
      return this.showError(error.message) // mismatched key or unreachable remote signer
    }
    if (!signer) return this.reportNoSigner()

    const item = this.templateTarget.content.firstElementChild.cloneNode(true)
    files.set(item, file) // retained so an errored upload can be retried without re-selecting
    this.gridTarget.appendChild(item)
    this.preview(item, file)
    this.setState(item, "uploading")
    this.syncChrome()

    await this.uploadInto(item, file, signer)
  }

  // Re-attempt the upload for one errored card against its retained File (no re-selecting).
  async retry(event) {
    const item = event.currentTarget.closest('[data-image-upload-target="item"]')
    if (!item) return
    const file = files.get(item)
    if (!file) return this.showError("That image is no longer available. Remove it and add it again.")
    if (this.liveCount() >= MAX) return this.showError(`You can add up to ${MAX} images.`)

    let signer
    try {
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
    } catch (error) {
      return this.showError(error.message)
    }
    if (!signer) return this.reportNoSigner()

    this.clearError()
    this.setState(item, "uploading")
    this.syncChrome() // the card counts toward the cap again while in flight
    await this.uploadInto(item, file, signer)
  }

  // Run the Blossom upload for an already-rendered "uploading" card and land it in done/error.
  async uploadInto(item, file, signer) {
    try {
      const meta = await uploadImage(file, signer)
      this.fill(item, meta)
      this.setState(item, "done")
      this.dispatch("changed")
    } catch (error) {
      this.setState(item, "error", error.message)
      this.syncChrome() // a failed card no longer counts toward the cap
    }
  }

  remove(event) {
    event.currentTarget.closest('[data-image-upload-target="item"]')?.remove()
    this.syncChrome()
    this.dispatch("changed")
  }

  // Promote a thumbnail to the front so it becomes the cover.
  makeCover(event) {
    const item = event.currentTarget.closest('[data-image-upload-target="item"]')
    if (item) this.gridTarget.prepend(item)
    this.syncChrome()
    this.dispatch("changed")
  }

  // --- helpers ---

  // A null signer means: the user declined the unlock (stay quiet), or there is no usable credential.
  reportNoSigner() {
    if (savedMethod() === "nsec" && needsUnlock(this.pubkeyValue)) return this.clearError() // declined the unlock prompt
    if (lostNsecSession(this.pubkeyValue)) return this.showError("Your key was cleared on reload. Sign in again to upload.")
    if (savedMethod() === "nip07") return this.showError("Your Nostr extension isn't available. Unlock it, then retry.")
    this.showError("Connect or unlock your signer to upload images.")
  }

  validate(file) {
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) return "Use a PNG, JPEG, WebP, or GIF image."
    if (file.size > MAX_IMAGE_BYTES) return "Image is too large (max 20 MiB)."
    return null
  }

  preview(item, file) {
    const reader = new FileReader()
    reader.onload = () => { item.querySelector('[data-role="img"]').src = reader.result }
    reader.readAsDataURL(file) // data: URL keeps us within img-src 'self' data: https (blob: is not allowed)
  }

  fill(item, meta) {
    item.querySelector('[data-field="url"]').value = meta.url || ""
    item.querySelector('[data-field="m"]').value = meta.m || ""
    item.querySelector('[data-field="x"]').value = meta.x || ""
    item.querySelector('[data-field="dim"]').value = meta.dim || ""
  }

  // An in-flight or errored card keeps its url input empty, so the server-side Draft simply drops it. The
  // message goes to a dedicated text node so the error-only action buttons (Retry/Remove) survive re-renders.
  setState(item, state, message = "") {
    item.dataset.state = state
    const overlay = item.querySelector('[data-role="status"]')
    if (!overlay) return
    overlay.hidden = state === "done"
    const text = overlay.querySelector('[data-role="status-text"]')
    if (text) {
      text.textContent = state === "error" ? message : "Uploading…"
      text.classList.toggle("text-lamp-fault", state === "error")
      text.classList.toggle("text-ink-secondary", state !== "error")
    }
    const actions = overlay.querySelector('[data-role="status-actions"]')
    if (actions) actions.hidden = state !== "error"
  }

  // Count only uploading/done cards toward the cap: a failed card is dead weight, not a used slot.
  liveCount() {
    return Array.from(this.gridTarget.children).filter((item) => item.dataset.state !== "error").length
  }

  full() {
    return this.liveCount() >= MAX
  }

  syncChrome() {
    const items = Array.from(this.gridTarget.children)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = items.length > 0
    if (this.hasAddTarget) this.addTarget.disabled = this.full()
    items.forEach((item, i) => {
      const badge = item.querySelector('[data-role="cover"]')
      if (badge) badge.hidden = i !== 0
      const cover = item.querySelector('[data-action~="image-upload#makeCover"]')
      if (cover) cover.hidden = i === 0
    })
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
