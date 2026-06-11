import { Controller } from "@hotwired/stimulus"

// The top-bar notifications bell. Opening the dropdown marks everything seen (clears the badge now, persists
// in the background). New notifications arrive via the per-user Turbo Stream (prepended to the list + the
// badge replaced); a MutationObserver hides the empty-state once the list has rows, and each badge replacement
// is announced into a polite live region for screen readers.
export default class extends Controller {
  static values = { seenUrl: String }
  static targets = ["badge", "list", "empty", "status"]

  connect() {
    this.observer = new MutationObserver(() => this.refreshEmpty())
    if (this.hasListTarget) this.observer.observe(this.listTarget, { childList: true })
    this.refreshEmpty()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // The badge element is swapped on every Turbo broadcast (new notification / mark-seen). Announce the new
  // unseen count to screen readers -- but not the initial page-load render, only subsequent live updates.
  badgeTargetConnected(element) {
    const count = parseInt(element.textContent, 10) || 0
    if (this.announced && this.hasStatusTarget) {
      this.statusTarget.textContent = count > 0 ? element.textContent.replace(/\s+/g, " ").trim() : ""
    }
    this.announced = true
  }

  // Opening the dropdown marks everything seen: clear the badge optimistically, persist best-effort. If the
  // request fails, restore the badge so the UI does not falsely read as caught-up (the next render is the
  // server's word either way).
  open() {
    this.setBadgeHidden(true)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.seenUrlValue, { method: "POST", headers: { "X-CSRF-Token": token || "" } })
      .then((response) => { if (!response.ok) this.setBadgeHidden(false) })
      .catch(() => this.setBadgeHidden(false))
  }

  setBadgeHidden(hidden) {
    if (this.hasBadgeTarget) this.badgeTarget.hidden = hidden
  }

  // Hide the empty-state once any real notification row is present (incl. a live-prepended one).
  refreshEmpty() {
    if (this.hasEmptyTarget) this.emptyTarget.hidden = Boolean(this.hasRows)
  }

  get hasRows() {
    return this.hasListTarget && this.listTarget.querySelector("[id^='notification_']")
  }
}
