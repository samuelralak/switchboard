import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"
import { normalizeRelayUrl } from "nostr/relay_url"

// NIP-65 projection cap (Users::RelayListUpsert::MAX_RELAY_TAGS): a larger list stores nothing server-side,
// so the editor enforces it here rather than letting a too-long list publish and silently fail to project.
const MAX_RELAYS = 20

// The non-custodial relay-list editor: hydrate the row list from the prefill, let the user add/remove relays
// and toggle their read/write roles, then sign + broadcast a kind-10002 with their key (nothing is POSTed to
// Rails). After a successful broadcast it PATCHes the settings resource so the server force-fetches the new
// list back and the projection catches up. Rows share one markup source (the <template>), cloned on connect
// for the prefill and again on add. Mirrors profile-form.
export default class extends Controller {
  static values = { pubkey: String, relays: Array, rows: Array, refreshUrl: String }
  static targets = ["list", "rowTemplate", "row", "newUrl", "status", "submit"]

  connect() {
    if (this.hydrated) return
    this.hydrated = true
    this.rowsValue.forEach((row) => this.appendRow(row))
  }

  addRow(event) {
    event?.preventDefault()
    // Canonicalize first, so the dedup check + the stored url match the server's form (casing/trailing-slash
    // variants of an existing relay are caught rather than published as a phantom duplicate).
    const url = normalizeRelayUrl(this.newUrlTarget.value)
    if (!url) return this.setStatus("Enter a relay URL that starts with wss://", true)
    if (this.urls().includes(url)) return this.setStatus("That relay is already in your list.", true)
    if (this.rowTargets.length >= MAX_RELAYS) return this.setStatus(`A relay list holds at most ${MAX_RELAYS} relays.`, true)

    this.appendRow({ url, read: true, write: true })
    this.newUrlTarget.value = ""
    this.clearStatus()
  }

  removeRow(event) {
    event.currentTarget.closest('[data-relay-form-target="row"]')?.remove()
  }

  // Clone the single row template, fill it from { url, read, write }, and append it to the list.
  appendRow({ url, read, write }) {
    const node = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
    node.querySelector('[data-field="url"]').value = url
    const host = node.querySelector('[data-role="host"]')
    if (host) host.textContent = url.replace(/^wss?:\/\//i, "")
    node.querySelector('[data-field="read"]').checked = Boolean(read)
    node.querySelector('[data-field="write"]').checked = Boolean(write)
    this.listTarget.appendChild(node)
  }

  urls() {
    return this.rowTargets.map((row) => row.querySelector('[data-field="url"]').value)
  }

  // The current rows as [{ url, read, write }] for the publisher.
  collect() {
    return this.rowTargets.map((row) => ({
      url: row.querySelector('[data-field="url"]').value,
      read: row.querySelector('[data-field="read"]').checked,
      write: row.querySelector('[data-field="write"]').checked,
    }))
  }

  async publish(event) {
    event.preventDefault()
    if (this.publishing) return

    const rows = this.collect().filter((row) => row.read || row.write)
    if (rows.length > MAX_RELAYS) return this.setStatus(`A relay list holds at most ${MAX_RELAYS} relays.`, true)

    this.publishing = true
    this.setBusy(true)
    this.setStatus("Publishing…", false)
    try {
      const signer = await ensureSignerFor(this.pubkeyValue, { prompt: true })
      if (!signer) return this.fail("Connect or unlock your signer to publish.")

      const { broadcastRelayList } = await import("nostr/relay_publish")
      const result = await broadcastRelayList(rows, signer, this.relaysValue)
      if (result.reached === 0) throw new Error("Couldn't reach any relay. Try again.")

      this.succeed(result.reached)
      this.requestRefresh()
    } catch (error) {
      this.fail(error.message || "Couldn't publish your relays.")
    } finally {
      this.publishing = false
      this.setBusy(false)
    }
  }

  // Ask the server to reconcile (PATCH the relays resource): force-fetch the just-broadcast kind-10002 back,
  // bypassing the login cooldown. Best-effort -- the DB also catches up on the next login fetch.
  requestRefresh() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.refreshUrlValue, {
      method: "PATCH",
      headers: { "X-CSRF-Token": token || "", Accept: "application/json" },
    }).catch(() => {})
  }

  succeed(reached) {
    this.setStatus(`Published to ${reached} relay${reached === 1 ? "" : "s"}. Your list updates across the app once a relay serves it back.`, false)
  }

  fail(message) {
    this.setStatus(message, true)
  }

  clearStatus() {
    if (this.hasStatusTarget) this.statusTarget.hidden = true
  }

  setStatus(message, isError) {
    if (!this.hasStatusTarget) return
    const el = this.statusTarget
    el.textContent = message
    el.hidden = false
    el.classList.toggle("border-lamp-fault/40", isError)
    el.classList.toggle("bg-lamp-fault/5", isError)
    el.classList.toggle("border-border", !isError)
    el.classList.toggle("bg-surface-2", !isError)
    el.classList.add("text-ink-secondary")
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = busy
  }
}
