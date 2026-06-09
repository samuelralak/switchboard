import { Controller } from "@hotwired/stimulus"
import { DmClient, canMessage } from "nostr/dm_client"
import { ensureSignerFor, lostNsecSession } from "nostr/signer_store"

// Stimulus DOM wrapper around the DmClient engine. Reads the signed-in
// pubkey, DM relays, and inbox URL from data-* values, and takes the active signer from the tab-scoped
// registry (NIP-07 / nsec / bunker, re-hydrated on a hard reload), gates on a NIP-44 capability
// self-test, then wires the compose form to send() and incoming rumors into the thread. Decrypted text
// is rendered client-side and never sent back to Rails.
export default class extends Controller {
  static values = { pubkey: String, relays: Array, inboxUrl: String }
  static targets = ["peer", "body", "thread", "status", "form", "locked", "lockedNote", "unlockButton"]

  async connect() {
    this.active = true // cleared by disconnect(); guards the async startWith against a navigate-away race
    this.setBusy(true) // keep the form inert until the client is actually ready
    let signer
    try {
      // prompt:false: a passive page load must never auto-pop the unlock dialog. A locked/absent signer
      // returns null, and we show a quiet inline affordance the user clicks to unlock (gesture-backed).
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: false })
    } catch (error) {
      return this.disable(error.message) // identity mismatch on a live signer
    }
    if (!signer) return this.showLocked()
    await this.startWith(signer)
  }

  // The inline affordance's button is a real user gesture, so prompting (the nsec passphrase dialog, a
  // nip07/bunker re-acquire) is allowed here. On success, hide the affordance and start the client.
  async unlock() {
    if (this.starting || this.client) return // a double-click must not start a second client
    let signer
    try {
      signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
    } catch (error) {
      return this.setLockedNote(error.message)
    }
    if (!signer) return // user dismissed the dialog: leave the affordance up, no noise
    this.hideLocked()
    await this.startWith(signer)
  }

  // Stand up the DmClient exactly once. The `starting`/`client` guard blocks re-entrancy (double-click),
  // and the `active` re-check after each await stops a client that was created while the user navigated
  // away (Turbo disconnect mid-start), so no orphaned subscription or relay socket leaks.
  async startWith(signer) {
    if (this.starting || this.client) return
    this.starting = true
    try {
      if (!(await canMessage(signer))) return this.disable("This signer can't encrypt messages (NIP-44 unavailable).")
      if (!this.active) return // disconnected during the capability check

      const client = new DmClient({
        signer,
        relays: this.relaysValue,
        inboxUrl: this.inboxUrlValue,
        onMessage: (rumor) => this.append(rumor),
        onStatus: (state) => this.reflectConnectivity(state),
      })
      this.client = client
      await client.start()
      if (!this.active) { client.stop(); this.client = null; return } // disconnected during start()
      this.setBusy(false)
      this.setStatus("Connected.")
    } catch {
      this.disable("Couldn't reach your relays.")
    } finally {
      this.starting = false
    }
  }

  // Live connectivity from the relay set: a frozen "Connected." while the inbox is silently dead is the
  // exact symptom we are fixing, so reflect drops and recoveries. The relay set keeps reconnecting either way.
  reflectConnectivity(state) {
    if (!this.active || !this.client) return

    if (state === "connected") return this.setStatus("Connected.")
    if (state === "degraded") return this.setStatus("Reconnecting…")

    this.setStatus("Connection lost. Reconnecting…")
  }

  showLocked() {
    if (this.hasFormTarget) this.formTarget.hidden = true
    if (this.hasLockedTarget) this.lockedTarget.hidden = false
    // A lost session has no saved ciphertext to unlock, so point at signing in again, not the passphrase dialog.
    if (lostNsecSession(this.pubkeyValue)) {
      this.setLockedNote("Your key was cleared on reload. Sign in again to load your messages.")
      if (this.hasUnlockButtonTarget) this.unlockButtonTarget.hidden = true
    }
  }

  hideLocked() {
    if (this.hasLockedTarget) this.lockedTarget.hidden = true
    if (this.hasFormTarget) this.formTarget.hidden = false
    this.setBusy(true) // startWith re-enables once connected
  }

  setLockedNote(message) {
    if (this.hasLockedNoteTarget) this.lockedNoteTarget.textContent = message
  }

  disconnect() {
    this.active = false // a startWith still in flight will stop the client it creates instead of leaking it
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
