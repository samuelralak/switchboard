import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// The consumer's funding flow on the order page: mint the budget over Lightning, lock it as an HTLC to
// the provider with a timelock refund, back up the unlock material, then submit the Turbo report form.
// All keys/preimage/token stay in the browser (brief sec 6.3); Rails only receives the observable report.
export default class extends Controller {
  static targets = [
    "start", "panel", "status", "invoice", "bolt11", "error", "form",
    "mintUrl", "hashlock", "locktime", "lockPubkey", "refundPubkey",
  ]
  static values = {
    orderId: String, mint: String, amount: Number, provider: String, consumer: String,
    relays: String, locktimeSeconds: Number,
  }

  async start() {
    this.startTarget.disabled = true
    this.panelTarget.classList.remove("hidden")
    this.clearError()

    try {
      await this.fund()
    } catch (error) {
      this.showError(error?.message || "Funding failed. Please try again.")
      this.startTarget.disabled = false
    }
  }

  async fund() {
    const relays = JSON.parse(this.relaysValue)
    const signer = await ensureSignerFor(this.consumerValue, { prompt: true })
    if (!signer) throw new Error("Unlock your signer to fund the escrow.")

    const funding = await import("nostr/order_funding")

    // Resume a prior attempt that already locked funds for this order (e.g. the backup or submit failed):
    // re-finish from the locally-saved lock. NEVER re-mint -- that would lock NEW funds and orphan the old.
    const saved = await funding.loadSecrets(this.orderIdValue)
    if (saved?.token && saved?.payload) {
      this.setStatus("Resuming your funding…")
      await funding.backupSecrets({ signer, ownPubkey: this.consumerValue, relays, orderId: this.orderIdValue, secrets: saved })
      await this.deliver(signer, relays, saved.token, saved.proofs)
      return this.submitReport(saved.payload)
    }

    this.setStatus("Setting up your escrow key…")
    const { ensureEscrowIdentity, discover } = await import("nostr/escrow_identity")
    const me = await ensureEscrowIdentity({
      accountPubkey: this.consumerValue, signer, relays, mints: [ this.mintValue ],
    })

    this.setStatus("Looking up the provider's escrow key…")
    const provider = await discover(this.providerValue, relays)
    if (!provider) throw new Error("The provider has not enabled escrow payments yet.")
    if (provider.mints.length && !provider.mints.includes(this.mintValue)) {
      throw new Error("The provider does not accept this mint.")
    }

    const { Wallet } = await import("@cashu/cashu-ts")
    const wallet = new Wallet(this.mintValue, { unit: "sat" })
    const locktime = Math.floor(Date.now() / 1000) + this.locktimeSecondsValue

    const { payload, token, preimage, lockedProofs } = await funding.mintLockAndReport({
      wallet, mintUrl: this.mintValue, amount: this.amountValue,
      providerPubkey: provider.pubkey, consumerRefundPubkey: me.pubkeyHex, locktime,
      onInvoice: (bolt11) => this.showInvoice(bolt11),
      onStatus: (stage) => this.setStatus(STATUS[stage] || stage),
    })

    // backupSecrets persists locally (mandatory) before the relay self-DM, and stores the payload + proofs
    // so a resume can re-deliver + re-submit without re-minting.
    this.setStatus("Backing up your escrow secrets…")
    await funding.backupSecrets({
      signer, ownPubkey: this.consumerValue, relays, orderId: this.orderIdValue,
      secrets: { token, preimage, mint: this.mintValue, locktime, payload, proofs: lockedProofs },
    })

    await this.deliver(signer, relays, token, lockedProofs)
    this.submitReport(payload)
  }

  // Hand the locked budget to the provider over NIP-17 so they can verify it now and redeem on release.
  async deliver(signer, relays, token, proofs) {
    this.setStatus("Delivering the locked budget to the provider…")
    const { sendEscrowMessage } = await import("nostr/escrow_messages")
    await sendEscrowMessage({
      signer, ownPubkey: this.consumerValue, peerPubkey: this.providerValue, relays,
      orderId: this.orderIdValue, type: "token-delivery", data: { token, proofs },
    })
  }

  submitReport(payload) {
    this.setStatus("Recording the lock…")
    this.fillForm(payload)
    this.formTarget.requestSubmit()
  }

  fillForm(payload) {
    this.mintUrlTarget.value = payload.mint_url
    this.hashlockTarget.value = payload.hashlock
    this.locktimeTarget.value = payload.locktime
    this.lockPubkeyTarget.value = payload.lock_pubkey
    this.refundPubkeyTarget.value = payload.refund_pubkey

    payload.proofs.forEach((proof) => this.appendProof(proof))
  }

  // Rails reads order[proofs][] as an array of hashes: emit y, amount, keyset_id in order so a repeated
  // key starts the next proof.
  appendProof({ y, amount, keyset_id }) {
    for (const [ key, value ] of [ [ "y", y ], [ "amount", amount ], [ "keyset_id", keyset_id ] ]) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = `order[proofs][][${key}]`
      input.value = value
      this.formTarget.appendChild(input)
    }
  }

  showInvoice(bolt11) {
    this.invoiceTarget.classList.remove("hidden")
    this.bolt11Target.value = bolt11
  }

  copy() {
    navigator.clipboard?.writeText(this.bolt11Target.value)
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  showError(text) {
    this.errorTarget.textContent = text
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}

const STATUS = {
  invoice: "Waiting for the Lightning payment…",
  waiting: "Waiting for the Lightning payment…",
  minting: "Minting ecash…",
  locking: "Locking the escrow…",
}
