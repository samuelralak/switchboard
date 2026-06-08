import { Controller } from "@hotwired/stimulus"

// A live countdown to a unix-seconds deadline, rendered into this element's text. Ticks once a second and
// stops at zero (showing "now"), so a lifecycle deadline (funding window, refund timelock) stays current
// without a reload. Pure display; the actual deadline is enforced by the mint/server.
export default class extends Controller {
  static values = { deadline: Number }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = this.deadlineValue - Math.floor(Date.now() / 1000)
    if (remaining <= 0) {
      this.element.textContent = "now"
      clearInterval(this.timer)
      return
    }
    this.element.textContent = format(remaining)
  }
}

// "2d 03:14:05" past a day, else "03:14:05".
function format(seconds) {
  const days = Math.floor(seconds / 86_400)
  const hours = Math.floor((seconds % 86_400) / 3_600)
  const minutes = Math.floor((seconds % 3_600) / 60)
  const secs = seconds % 60
  const clock = [ hours, minutes, secs ].map((n) => String(n).padStart(2, "0")).join(":")
  return days > 0 ? `${days}d ${clock}` : clock
}
