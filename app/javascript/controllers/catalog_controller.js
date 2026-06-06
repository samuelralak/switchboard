import { Controller } from "@hotwired/stimulus"

// Client-side marketplace browser for the catalog: one "ask for anything" search over two lenses —
// Services (supply) and Open requests (demand) — plus a fulfillment-mode filter (services only) and a
// sort, all instant and reload-free. Cards declare data-type ("service" | "request"); the active lens
// (view) shows one type at a time. Live cards streamed in via Turbo are filtered on connect, so the
// active lens + filter keep applying as new listings/requests arrive. Also drives the single-lens
// My-requests page (set data-catalog-view-value="request", no tabs).
export default class extends Controller {
  static targets = ["query", "card", "count", "empty", "modeButton", "modeFilter", "tab", "viewSelect", "clear", "results", "list", "sortLabel"]
  static values = {
    mode: { type: String, default: "all" },
    sort: { type: String, default: "newest" },
    view: { type: String, default: "service" },
  }

  connect() {
    this.autogrow()
    this.updateQueryState()
    this.syncView()
    this.apply()
  }

  filter() {
    this.autogrow()
    this.apply()
  }

  setMode(event) {
    this.modeValue = event.currentTarget.dataset.mode
  }

  setSort(event) {
    this.sortValue = event.currentTarget.dataset.sort
    if (this.hasSortLabelTarget) this.sortLabelTarget.textContent = event.currentTarget.textContent.trim()
  }

  // Switch the lens (Services <-> Open requests). The search box filters whichever lens is active.
  setView(event) {
    this.viewValue = event.currentTarget.dataset.view
  }

  // The mobile <select> mirrors the desktop tabs.
  setViewFromSelect(event) {
    this.viewValue = event.target.value
  }

  // Clear the query and re-focus, returning the catalog to its full set.
  clear() {
    if (!this.hasQueryTarget) return
    this.queryTarget.value = ""
    this.queryTarget.focus()
    this.autogrow()
    this.apply()
  }

  // "Route it" (button submit): apply the filter and bring the matches into view.
  // Without JS the form submits normally and the server narrows by ?q=.
  route(event) {
    event.preventDefault()
    this.routeToResults()
  }

  // Cmd/Ctrl + Enter submits the composer; Enter alone inserts a newline.
  submitShortcut(event) {
    if (event.key !== "Enter" || !(event.metaKey || event.ctrlKey)) return
    event.preventDefault()
    this.routeToResults()
  }

  routeToResults() {
    this.apply()
    if (!this.hasResultsTarget) return
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.resultsTarget.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
  }

  // "/" anywhere focuses the catalog search, the page's single search surface.
  focusSearch(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    const el = document.activeElement
    if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || el.isContentEditable)) return
    if (!this.hasQueryTarget) return
    event.preventDefault()
    this.queryTarget.focus()
    this.queryTarget.select()
  }

  // Re-apply the current filter (and re-sort) to a card added live via Turbo Stream.
  cardTargetConnected(card) {
    this.applyToCard(card)
    this.updateCount()
    this.scheduleSort()
  }

  modeValueChanged() {
    this.updateModeButtons()
    this.apply()
  }

  sortValueChanged() {
    this.applySort()
  }

  viewValueChanged() {
    this.syncView()
    this.apply()
    this.scheduleSort()
  }

  // Reorder rows in place by the active sort, within EACH lens's list container independently (so a
  // price/budget sort never interleaves services with requests). Newest = the server order (and live
  // prepends already arrive newest-first), so only a price sort reorders the DOM.
  applySort() {
    if (!this.hasListTarget) return
    const key = (card, attr) => Number(card.dataset[attr] || 0)
    const cmp = {
      "price-asc": (a, b) => key(a, "price") - key(b, "price"),
      "price-desc": (a, b) => key(b, "price") - key(a, "price"),
      newest: (a, b) => key(b, "created") - key(a, "created"),
    }[this.sortValue] || (() => 0)
    this.listTargets.forEach((list) => {
      [...list.children].filter((c) => c.matches('[data-catalog-target="card"]')).sort(cmp).forEach((c) => list.appendChild(c))
    })
  }

  // Coalesce a flood of live-prepend re-sorts into one frame; skip when newest (already ordered).
  scheduleSort() {
    if (this.sortValue === "newest") return
    cancelAnimationFrame(this.sortFrame)
    this.sortFrame = requestAnimationFrame(() => this.applySort())
  }

  apply() {
    this.cardTargets.forEach((card) => this.applyToCard(card))
    this.updateCount()
    this.updateQueryState()
  }

  // Reveal the clear button only once there's a query.
  updateQueryState() {
    const hasText = this.hasQueryTarget && this.queryTarget.value.trim() !== ""
    if (this.hasClearTarget) this.clearTarget.hidden = !hasText
  }

  // Grow the composer textarea to fit its content (capped by max-height in CSS).
  autogrow() {
    if (!this.hasQueryTarget) return
    const field = this.queryTarget
    field.style.height = "auto"
    field.style.height = `${field.scrollHeight}px`
  }

  applyToCard(card) {
    // A card shows when it belongs to the active lens AND clears the search/mode filters.
    const onLens = (card.dataset.type || "service") === this.viewValue
    // Inline display beats the card's `flex` utility, so hiding is reliable.
    card.style.display = onLens && this.matchesFilters(card) ? "" : "none"
  }

  // Filter match independent of the active lens (query + mode), so a tab's count reflects how many it
  // holds even while the other lens is showing.
  matchesFilters(card) {
    const query = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()
    const text = card.dataset.search || ""
    const type = card.dataset.type || "service"
    const cardMode = card.dataset.mode || "unknown"
    return (query === "" || text.includes(query)) &&
      (type !== "service" || this.modeValue === "all" || cardMode === this.modeValue) // mode filters services only
  }

  // Active-lens styling on the tabs (copper underline + count badge), the mobile select's value, and the
  // mode filter's visibility (off the Open-requests lens).
  syncView() {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.view === this.viewValue
      tab.setAttribute("aria-selected", String(active))
      tab.classList.toggle("border-copper", active)
      tab.classList.toggle("text-ink", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-ink-muted", !active)
      const badge = tab.querySelector('[data-role="count"]')
      if (badge) {
        badge.classList.toggle("bg-copper/15", active)
        badge.classList.toggle("text-copper", active)
        badge.classList.toggle("bg-inset", !active)
        badge.classList.toggle("text-ink-secondary", !active)
      }
    })
    if (this.hasViewSelectTarget) this.viewSelectTarget.value = this.viewValue
    if (this.hasModeFilterTarget) this.modeFilterTarget.hidden = this.viewValue !== "service"
  }

  updateModeButtons() {
    this.modeButtonTargets.forEach((button) => {
      const active = button.dataset.mode === this.modeValue
      button.classList.toggle("bg-surface-2", active)
      button.classList.toggle("text-ink", active)
      button.classList.toggle("text-ink-muted", !active)
    })
  }

  updateCount() {
    // Count by lens using the lens-independent filter, so each tab shows its own total (not just the
    // active lens's visible rows).
    const countOf = (type) => this.cardTargets.filter((c) => (c.dataset.type || "service") === type && this.matchesFilters(c)).length
    if (this.hasTabTarget) {
      this.tabTargets.forEach((tab) => {
        const el = tab.querySelector('[data-role="count"]')
        if (el) el.textContent = countOf(tab.dataset.view)
      })
    } else if (this.hasCountTarget) {
      this.countTarget.textContent = countOf(this.viewValue)
    }
    // Per-lens empty state: show the active lens's empty block when nothing in it matches.
    this.emptyTargets.forEach((empty) => {
      const view = empty.dataset.view || this.viewValue
      empty.hidden = !(view === this.viewValue && countOf(view) === 0)
    })
  }
}
