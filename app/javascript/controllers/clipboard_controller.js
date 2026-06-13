import { Controller } from "@hotwired/stimulus"

// Copy a fixed value (data-clipboard-text-value) to the clipboard and briefly confirm via a label target.
// Used by the donation page's Lightning / on-chain address rows.
export default class extends Controller {
  static values = { text: String }
  static targets = [ "label" ]

  copy() {
    if (!navigator.clipboard) return

    navigator.clipboard.writeText(this.textValue).then(() => this.confirm())
  }

  confirm() {
    if (!this.hasLabelTarget) return

    const original = this.labelTarget.textContent
    this.labelTarget.textContent = "Copied"
    setTimeout(() => { this.labelTarget.textContent = original }, 1200)
  }
}
