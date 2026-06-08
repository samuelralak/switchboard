import { Controller } from "@hotwired/stimulus"

// Closes a URL-driven overlay (the order drawer) on Escape by navigating to its close URL, keeping the
// drawer's open state in sync with the address bar (the backdrop + close button are plain links to the
// same URL). Turbo Drive makes the navigation snappy.
export default class extends Controller {
  static values = { url: String }

  close() {
    window.Turbo.visit(this.urlValue, { action: "replace" })
  }
}
