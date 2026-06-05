import { Controller } from "@hotwired/stimulus"
import { DmClient, canMessage } from "nostr/dm_client"
import { Nip07Signer } from "nostr/signer"

// Stimulus DOM wrapper around the DmClient engine for the #32 generic DM proof. Reads the signed-in
// pubkey, DM relays, and inbox URL from data-* values, uses the NIP-07 extension as the session signer
// (nsec/bunker messaging is a later refinement -- login disposes those one-shot), gates on a NIP-44
// capability self-test, then wires the compose form to send() and incoming rumors into the thread.
// Decrypted text is rendered client-side and never sent back to Rails.
export default class extends Controller {
  static values = { pubkey: String, relays: Array, inboxUrl: String }
  static targets = ["peer", "body", "thread", "status", "form"]

  async connect() {
    this.setBusy(true) // keep the form inert until the client is actually ready
    const signer = Nip07Signer.available() ? new Nip07Signer() : null
    if (!signer) return this.disable("Connect a NIP-07 extension (Alby, nos2x) to send messages.")
    if (!(await canMessage(signer))) return this.disable("This signer can't encrypt messages (NIP-44 unavailable).")

    this.client = new DmClient({
      signer,
      relays: this.relaysValue,
      inboxUrl: this.inboxUrlValue,
      onMessage: (rumor) => this.append(rumor),
    })
    try {
      await this.client.start()
      this.setBusy(false)
      this.setStatus("Connected.")
    } catch {
      this.disable("Couldn't reach your relays.")
    }
  }

  disconnect() {
    this.client?.stop()
    this.client = null
  }

  async send(event) {
    event.preventDefault()
    if (!this.client) return this.setStatus("Still connecting…")
    const peer = this.peerTarget.value.trim()
    const body = this.bodyTarget.value
    if (!/^[0-9a-f]{64}$/.test(peer)) return this.setStatus("Enter the recipient's 64-hex pubkey.")
    if (!body) return

    this.setStatus("Sending…")
    try {
      await this.client.send(peer, body)
      this.bodyTarget.value = ""
      this.setStatus("Sent.")
    } catch (error) {
      this.setStatus(error.message)
    }
  }

  append(rumor) {
    if (!this.hasThreadTarget) return
    const item = document.createElement("li")
    item.textContent = rumor.content
    this.threadTarget.appendChild(item)
  }

  setBusy(busy) {
    this.formTarget?.querySelectorAll("input, textarea, button").forEach((element) => { element.disabled = busy })
  }

  disable(message) {
    this.setStatus(message)
    this.setBusy(true)
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
