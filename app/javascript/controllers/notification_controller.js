import { Controller } from "@hotwired/stimulus"

// A single unread notification row. Clicking it marks the notification read; the link still navigates to the
// order. keepalive lets the PATCH outlive the navigation. Attached only to UNREAD rows, so an already-read
// row issues no request. Self-contained per row, so it works in both the bell dropdown and the full feed.
export default class extends Controller {
  static values = { url: String }

  open() {
    if (!this.urlValue) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, { method: "PATCH", headers: { "X-CSRF-Token": token || "" }, keepalive: true })
      .then((response) => { if (!response.ok) console.warn(`notification mark-read failed: ${response.status}`) })
      .catch((error) => console.warn("notification mark-read failed:", error))
  }
}
