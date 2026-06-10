import { Controller } from "@hotwired/stimulus"

// Scrolls the active descendant ([aria-current]) into view within this container on connect, so the current
// item is visible on a narrow horizontally-scrolling rail (e.g. the mobile settings rail). On a desktop
// column the active item is already visible, so block:"nearest" makes this a no-op there.
export default class extends Controller {
  connect() {
    this.element.querySelector("[aria-current]")?.scrollIntoView({ block: "nearest", inline: "center" })
  }
}
