import { Controller } from "@hotwired/stimulus"
import { ensureSignerFor } from "nostr/signer_store"

// The consumer's funding flow on the order page: mint the budget over Lightning, lock it as an HTLC to
// the provider with a timelock refund, back up the unlock material, then submit the Turbo report form.
// All keys/preimage/token stay in the browser (brief sec 6.3); Rails only receives the observable report.
export default class extends Controller {
  static targets = [
    "start", "panel", "status", "invoice", "qr", "bolt11", "error", "form",
    "mintUrl", "locktime", "lockPubkey", "refundPubkey",
  ]
  static values = {
    orderId: String, mint: String, amount: Number, provider: String, consumer: String,
    relays: String, locktimeSeconds: Number, tier: String, arbiter: String,
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

    // Resume a prior attempt that already locked funds for this order (e.g. a crash after the lock, before the
    // report/backup/submit): re-finish from the locally-saved lock. The marker is written the instant funds
    // lock, so ANY saved token means funds are already at the mint -- NEVER re-mint (that would lock NEW funds
    // and orphan the old). Re-derive the report if the crash landed before it (saved.token but no saved.payload).
    const saved = await funding.loadSecrets(this.orderIdValue)
    if (saved?.token) {
      this.setStatus("Resuming your funding…")
      let payload = saved.payload
      if (!payload) {
        const { Wallet } = await import("@cashu/cashu-ts")
        payload = await funding.reportFromSaved(new Wallet(this.mintValue, { unit: "sat" }), saved)
      }
      await funding.backupSecrets({ signer, ownPubkey: this.consumerValue, relays, orderId: this.orderIdValue, secrets: { ...saved, payload } })
      await this.deliver(signer, relays, saved.token, saved.proofs)
      return this.submitReport(payload)
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

    const { payload, token, preimage, lockedProofs } = await this.mintAndLock(funding, wallet, me, provider, locktime, signer, relays)

    // backupSecrets persists locally (mandatory) before the relay self-DM, and stores the payload + proofs
    // so a resume can re-deliver + re-submit without re-minting. Tier-2 has no preimage; omit it.
    this.setStatus("Backing up your escrow secrets…")
    const secrets = { token, mint: this.mintValue, locktime, payload, proofs: lockedProofs }
    if (preimage) secrets.preimage = preimage
    await funding.backupSecrets({ signer, ownPubkey: this.consumerValue, relays, orderId: this.orderIdValue, secrets })

    await this.deliver(signer, relays, token, lockedProofs)
    this.submitReport(payload)
  }

  // Mint the budget and lock it for the order's tier. Tier-2 (2-of-3 arbiter) locks the consumer escrow key
  // as a signer + the provider + the PLATFORM arbiter, no hashlock; tier-1 locks an HTLC to the provider.
  // me.pubkeyHex (the consumer ESCROW key) is both the 2-of-3 consumer signer and the timelock-refund key.
  async mintAndLock(funding, wallet, me, provider, locktime, signer, relays) {
    const onInvoice = (bolt11) => this.showInvoice(bolt11)
    const onStatus = (stage) => this.setStatus(STATUS[stage] || stage)
    const backup = (proofs) => this.backupMinted(funding, signer, relays, proofs)
    const common = { wallet, mintUrl: this.mintValue, amount: this.amountValue, locktime, orderId: this.orderIdValue, onInvoice, onStatus, backup }

    if (this.tierValue === TIER2_ARBITER) {
      // Source the arbiter from Rails (data-value); locking to any other key orphans the funds (Orders::Funding
      // VALIDATES arbiter == the platform key and rejects the report AFTER the mint has locked them).
      if (!this.arbiterValue) throw new Error("Mediated escrow is unavailable right now.")

      return funding.mintLockAndReportTier2({
        ...common, consumerPubkey: me.pubkeyHex, providerPubkey: provider.pubkey,
        arbiterPubkey: this.arbiterValue, consumerRefundPubkey: me.pubkeyHex,
      })
    }

    return funding.mintLockAndReport({ ...common, providerPubkey: provider.pubkey, consumerRefundPubkey: me.pubkeyHex })
  }

  // Best-effort relay backup of the freshly minted (pre-lock) proofs, so the ecash survives device loss in the
  // brief mint -> lock window, not just a same-browser reload. They are already in local IndexedDB; a relay
  // failure must NOT block funding, so this swallows errors (the encrypted self-DM copy is the cross-device bonus).
  async backupMinted(funding, signer, relays, proofs) {
    try {
      await funding.backupSecrets({
        signer, ownPubkey: this.consumerValue, relays, orderId: this.orderIdValue,
        secrets: { stage: "minted", mint: this.mintValue, mintedProofs: proofs },
      })
    } catch {
      // already persisted locally; the relay copy is best-effort here
    }
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
    this.locktimeTarget.value = payload.locktime
    this.lockPubkeyTarget.value = payload.lock_pubkey
    this.refundPubkeyTarget.value = payload.refund_pubkey

    // Tier-specific lock terms, by presence: tier-1 carries hashlock; tier-2 carries arbiter_pubkey +
    // required_signatures and NO hashlock (an empty hashlock would be rejected by the tier-2 contract).
    for (const key of [ "hashlock", "arbiter_pubkey", "required_signatures" ]) {
      if (payload[key] != null) this.appendField(`order[${key}]`, payload[key])
    }

    payload.proofs.forEach((proof) => this.appendProof(proof))
  }

  // Rails reads order[proofs][] as an array of hashes: emit y, amount, keyset_id in order so a repeated
  // key starts the next proof.
  appendProof({ y, amount, keyset_id }) {
    for (const [ key, value ] of [ [ "y", y ], [ "amount", amount ], [ "keyset_id", keyset_id ] ]) {
      this.appendField(`order[proofs][][${key}]`, value)
    }
  }

  appendField(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    this.formTarget.appendChild(input)
  }

  showInvoice(bolt11) {
    this.invoiceTarget.classList.remove("hidden")
    this.bolt11Target.value = bolt11
    this.renderQr(bolt11)
  }

  // Render the invoice as a scannable QR (lazy-imported, self-hosted). Convenience only: a failure must never
  // block funding, so it is fire-and-forget and swallows errors. Lightning QRs encode the bolt11 UPPERCASED in
  // alphanumeric mode (bech32 is case-insensitive) for a less dense, easier-to-scan code; the copyable text
  // below stays as issued.
  async renderQr(bolt11) {
    if (!this.hasQrTarget) return
    try {
      const { default: qrcode } = await import("qrcode-generator")
      const qr = qrcode(0, "M")
      qr.addData(bolt11.toUpperCase(), "Alphanumeric")
      qr.make()
      this.qrTarget.innerHTML = qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true })
      this.qrTarget.querySelector("svg")?.setAttribute("width", "100%")
      this.qrTarget.querySelector("svg")?.setAttribute("height", "100%")
    } catch {
      // QR is a convenience; the copyable invoice text remains if rendering fails
    }
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

// Mirrors Orders::Tiers::TIER2_ARBITER; the order's tier is rendered into data-funding-tier-value.
const TIER2_ARBITER = "tier2_arbiter"

const STATUS = {
  invoice: "Waiting for the Lightning payment…",
  waiting: "Waiting for the Lightning payment…",
  minting: "Minting ecash…",
  locking: "Locking the escrow…",
}
