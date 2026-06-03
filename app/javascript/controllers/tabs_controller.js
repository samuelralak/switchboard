import { Controller } from "@hotwired/stimulus"

// Minimal WAI-ARIA tabs: clicking or arrow-keying a tab shows its panel, marks it selected
// (aria-selected drives the styling), and moves the roving tabindex onto it. Runs on connect,
// so panels are correct before the dialog opens; without JS every panel stays visible
// (graceful fallback). Arrow/Home/End activate on focus -- automatic activation, which the
// WAI-ARIA tabs pattern recommends when panels are already in the DOM (no load latency).
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { selected: { type: Number, default: 0 } }

  select(event) {
    this.selectedValue = this.tabTargets.indexOf(event.currentTarget)
  }

  // Arrow keys move (and wrap) within the tablist; Home/End jump to the ends. Other keys
  // (Tab, Enter, Space) keep their native behavior.
  navigate(event) {
    const last = this.tabTargets.length - 1
    const targets = { ArrowRight: this.selectedValue + 1, ArrowLeft: this.selectedValue - 1, Home: 0, End: last }
    if (!(event.key in targets)) return
    event.preventDefault()
    this.selectedValue = (targets[event.key] + this.tabTargets.length) % this.tabTargets.length
    this.tabTargets[this.selectedValue].focus()
  }

  selectedValueChanged() {
    this.tabTargets.forEach((tab, index) => {
      const active = index === this.selectedValue
      tab.setAttribute("aria-selected", String(active))
      tab.tabIndex = active ? 0 : -1
      this.panelTargets[index]?.toggleAttribute("hidden", !active)
    })
  }
}
