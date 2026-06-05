import { Controller } from "@hotwired/stimulus"

// NIP-49 ncryptsec (the nsec encrypted with the user's passphrase). localStorage is never
// sent to the server, and only the ciphertext is stored -- the raw key never persists.
const STORED_KEY = "switchboard.nsec"

// Sign in with Nostr (NIP-98, kind 27235): the browser signs a server-issued single-use
// nonce and POSTs it to establish the Rails session. The nonce is prefetched on dialog open
// so window.nostr.signEvent runs inside the click gesture (strict NIP-07 signers reject it
// otherwise). The NIP-46 (bunker) and nsec paths are async and import nostr-tools lazily.
export default class extends Controller {
  // verifyUrl is the server-pinned canonical `u` (config.x.canonical_origin + session_path);
  // sessionUrl is the relative POST target so the request stays same-origin.
  static values = { challengeUrl: String, sessionUrl: String, verifyUrl: String }
  static targets = ["status", "bunkerUrl", "nsec", "savePassphrase", "unlockPassphrase",
                    "extensionButton", "extensionHint", "pasteForm", "unlockForm"]

  connect() {
    this.reflectSavedKey()
  }

  // Prefetch the nonce and reflect the detected extension / saved key when the dialog opens.
  async prepare() {
    this.setStatus("")
    this.reflectExtension()
    this.reflectSavedKey()
    await this.primeNonce()
  }

  // NIP-07 browser extension. Equivalent to the messaging-side Nip07Signer (nostr/signer.js), but kept
  // inline: signEvent must run inside the click gesture, and importing the adapter would either await
  // before signEvent (strict signers reject that) or eager-load nostr-tools on every page.
  signInWithExtension(event) {
    event.preventDefault()
    if (!window.nostr) {
      this.setStatus("No Nostr extension found. Install Alby or nos2x, or use a remote signer below.")
      return
    }
    this.signAndSubmit("Approve the signature in your extension…", (template) => window.nostr.signEvent(template))
  }

  // NIP-46 remote signer (bunker): a relay round-trip with remote approval, fully async.
  signInWithBunker(event) {
    event.preventDefault()
    const input = this.bunkerUrlTarget.value.trim()
    if (!input) {
      this.setStatus("Paste your bunker:// URL or a name@domain address.")
      return
    }
    this.signAndSubmit("Connecting to your signer…", (template) => this.bunkerSign(input, template))
  }

  // Pasted nsec: signs the login locally, optionally saving the key NIP-49-encrypted.
  signInWithNsec(event) {
    event.preventDefault()
    const nsec = this.nsecTarget.value.trim()
    if (!nsec.startsWith("nsec1")) {
      this.setStatus("Paste your nsec (it starts with “nsec1”).")
      return
    }
    this.signAndSubmit("Signing in…", (template) => this.pasteSign(nsec, template))
  }

  // Unlock the key saved on this device and sign with it. A bad passphrase fails the
  // NIP-49 decrypt (its Poly1305 tag), surfaced before the sign attempt.
  async unlockSavedKey(event) {
    event.preventDefault()
    const passphrase = this.unlockPassphraseTarget.value
    if (!passphrase) {
      this.setStatus("Enter your passphrase.")
      return
    }
    let secretKey
    try {
      const { decrypt } = await import("nostr-tools/nip49")
      secretKey = decrypt(this.savedKey, passphrase)
    } catch {
      this.setStatus("Incorrect passphrase.")
      return
    }
    this.signAndSubmit("Signing in…", (template) => this.finalize(secretKey, template))
  }

  // Remove the saved key and return to the paste form.
  forgetKey(event) {
    event.preventDefault()
    localStorage.removeItem(STORED_KEY)
    this.reflectSavedKey()
    this.setStatus("Saved key removed.")
  }

  // Consume the nonce, sign the templated event, and submit it. `sign` runs before the first
  // await so the extension's signEvent stays in the click gesture; the catch covers both a
  // synchronous throw and a rejected promise. The in-flight guard ignores a double-click, and
  // secrets are cleared whatever the outcome.
  async signAndSubmit(status, sign) {
    if (this.signing) return
    const nonce = this.takeNonce()
    if (!nonce) return
    this.signing = true
    this.setStatus(status)
    try {
      const signed = await sign(this.template(nonce))
      await this.submit(signed)
    } catch (error) {
      this.fail(error)
    } finally {
      this.signing = false
      this.clearSecrets()
    }
  }

  // NIP-46 remote signer via the shared Nip46Signer adapter (nostr/signer.js), lazy-imported so a page
  // that never signs in does not pull nostr-tools. Login connects-and-closes per use; the messaging
  // client holds its own Nip46Signer open for the session.
  async bunkerSign(input, template) {
    const { Nip46Signer } = await import("nostr/signer")
    const signer = await Nip46Signer.connect(input, {
      onauth: (url) => {
        window.open(url, "_blank", "noopener")
        this.setStatus("Approve the connection in your signer…")
      },
    })
    // close() covers connect() too, so a declined/failed connection tears the signer down.
    try {
      return await signer.signEvent(template)
    } finally {
      await signer.close?.()
    }
  }

  // Decode a pasted nsec, optionally save it NIP-49-encrypted, and sign.
  async pasteSign(nsec, template) {
    const { decode } = await import("nostr-tools/nip19")
    const { type, data } = decode(nsec)
    if (type !== "nsec" || data.length !== 32) throw new Error("not a valid nsec")

    const passphrase = this.hasSavePassphraseTarget ? this.savePassphraseTarget.value : ""
    if (passphrase) {
      const { encrypt } = await import("nostr-tools/nip49")
      localStorage.setItem(STORED_KEY, encrypt(data, passphrase))
    }
    return this.finalize(data, template)
  }

  // Sign with a locally-held key via the shared NsecSigner adapter, then dispose() to zero the key
  // bytes (the login path is one-shot; the messaging client holds its NsecSigner for the session).
  async finalize(secretKey, template) {
    const { NsecSigner } = await import("nostr/signer")
    const signer = new NsecSigner(secretKey)
    try {
      return signer.signEvent(template)
    } finally {
      signer.dispose()
    }
  }

  // The prefetched nonce, consumed once. Re-primes and returns null if it is missing.
  takeNonce() {
    if (!this.nonce) {
      this.setStatus("Preparing… try again in a moment.")
      this.primeNonce()
      return null
    }
    const nonce = this.nonce
    this.nonce = null
    return nonce
  }

  // Fetch a fresh single-use nonce. Kept separate from prepare() so fail() can re-prime
  // without wiping the failure message.
  async primeNonce() {
    this.nonce = null
    try {
      this.nonce = (await this.fetchChallenge()).challenge
    } catch {
      this.setStatus("Couldn't reach the server. Close and try again.")
    }
  }

  // Wipe the secret-bearing inputs (not the public bunker URL). Called after every attempt
  // and when the dialog closes.
  clearSecrets() {
    if (this.hasNsecTarget) this.nsecTarget.value = ""
    if (this.hasSavePassphraseTarget) this.savePassphraseTarget.value = ""
    if (this.hasUnlockPassphraseTarget) this.unlockPassphraseTarget.value = ""
  }

  // Dim the extension option and hint when no NIP-07 provider is present.
  reflectExtension() {
    const available = Boolean(window.nostr)
    if (this.hasExtensionButtonTarget) this.extensionButtonTarget.disabled = !available
    if (this.hasExtensionHintTarget) {
      this.extensionHintTarget.textContent = available ? "" : "No browser extension detected."
    }
  }

  // Show the unlock form when a key is saved on this device, otherwise the paste form.
  reflectSavedKey() {
    const saved = Boolean(this.savedKey)
    if (this.hasUnlockFormTarget) this.unlockFormTarget.hidden = !saved
    if (this.hasPasteFormTarget) this.pasteFormTarget.hidden = saved
  }

  get savedKey() {
    return localStorage.getItem(STORED_KEY)
  }

  template(nonce) {
    return {
      kind: 27235,
      created_at: Math.floor(Date.now() / 1000),
      content: "",
      tags: [
        ["u", this.verifyUrlValue],
        ["method", "POST"],
        ["challenge", nonce],
      ],
    }
  }

  async submit(signed) {
    this.setStatus("Signing in…")
    const response = await fetch(this.sessionUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrf(), Authorization: `Nostr ${btoa(JSON.stringify(signed))}` },
    })
    if (!response.ok) throw new Error(`sign-in rejected (${response.status})`)
    Turbo.visit(window.location.href, { action: "replace" })
  }

  fail(error) {
    console.error("[nostr-auth]", error)
    this.setStatus("Sign-in failed. Please try again.")
    this.primeNonce() // re-prime so the next click can sign without an extra round-trip
  }

  async fetchChallenge() {
    const response = await fetch(this.challengeUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrf(), Accept: "application/json" },
    })
    if (!response.ok) throw new Error(`challenge ${response.status}`)
    return response.json()
  }

  csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
