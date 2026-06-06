import { Controller } from "@hotwired/stimulus"

// CSP-safe broken-image fallback. A strict script-src blocks inline `onerror`, so a provider's dead
// image URL would otherwise leave the browser's broken-image glyph in the catalog. On load failure
// (or if the image already failed before this controller connected) we hide the image; when a
// `[data-image-fallback-placeholder]` element follows it, that placeholder is revealed in its place.
// Toggling Tailwind's `hidden` class (not the `hidden` attribute) because a display utility on the
// placeholder would otherwise out-specify the attribute.
export default class extends Controller {
  connect() {
    const img = this.element
    // `complete` with zero natural size means the load finished and failed before we could listen.
    if (img.complete && img.naturalWidth === 0) this.failed()
  }

  failed() {
    this.element.classList.add("hidden")
    const placeholder = this.element.nextElementSibling
    if (placeholder?.hasAttribute("data-image-fallback-placeholder")) placeholder.classList.remove("hidden")
  }
}
