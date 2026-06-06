import { Controller } from "@hotwired/stimulus"

// Client-side catalog filter: narrows the listing grid by a free-text query and
// a fulfillment mode (all / automated / manual), instantly and without a reload.
// Live cards prepended via Turbo are filtered on connect, so the active filter
// keeps applying as new listings stream in. (The LLM intent router is future
// work; this is an honest text filter over what's in the catalog.)
export default class extends Controller {
  static targets = ["query", "card", "count", "empty", "modeButton", "clear", "results", "list", "sortLabel"]
  static values = { mode: { type: String, default: "all" }, sort: { type: String, default: "newest" } }

  connect() {
    this.autogrow()
    this.updateQueryState()
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

  // Reorder the rows in place by the active sort. Newest = the server order (and live prepends already
  // arrive newest-first), so a price sort is the only one that reorders the DOM.
  applySort() {
    if (!this.hasListTarget) return
    const key = (card, attr) => Number(card.dataset[attr] || 0)
    const cmp = {
      "price-asc": (a, b) => key(a, "price") - key(b, "price"),
      "price-desc": (a, b) => key(b, "price") - key(a, "price"),
      newest: (a, b) => key(b, "created") - key(a, "created"),
    }[this.sortValue] || (() => 0)
    ;[...this.cardTargets].sort(cmp).forEach((card) => this.listTarget.appendChild(card))
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
    const query = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()
    const text = card.dataset.search || ""
    const cardMode = card.dataset.mode || "unknown"
    const matches =
      (query === "" || text.includes(query)) &&
      (this.modeValue === "all" || cardMode === this.modeValue)
    // Inline display beats the card's `flex` utility, so hiding is reliable.
    card.style.display = matches ? "" : "none"
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
    const visible = this.cardTargets.filter((card) => card.style.display !== "none").length
    if (this.hasCountTarget) this.countTarget.textContent = visible
    if (this.hasEmptyTarget) this.emptyTarget.hidden = !(this.cardTargets.length > 0 && visible === 0)
  }
}
