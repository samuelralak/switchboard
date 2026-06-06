import { finalizeEvent, getPublicKey, generateSecretKey } from "nostr-tools/pure"
import { conversationKey, encrypt, decrypt } from "nostr/nip44"

// A signer is the browser's bridge to a holder of a Nostr key. The key NEVER leaves its holder; a
// signer only exposes the operations NIP-17 needs. All ops may be async (a NIP-46 bunker is a relay
// round-trip), so callers MUST await them:
//
//   getPublicKey()                 -> 64-hex pubkey
//   signEvent(template)            -> signed event (the kind-13 seal, by the user's key)
//   nip44Encrypt(peerPub, text)    -> NIP-44 payload
//   nip44Decrypt(peerPub, payload) -> plaintext
//   canEncrypt()                   -> whether nip44 is available on this signer (OPTIONAL in 07/46)
//
// Three implementations live here: NsecSigner (a locally-held key: pasted-nsec + the test/interop
// signer), Nip07Signer (browser extension), and Nip46Signer (remote bunker).

export class NsecSigner {
  // secretKey: Uint8Array(32). Held for the session because messaging needs ongoing decryption.
  constructor(secretKey) {
    this.secretKey = secretKey
  }

  static fromHex(hex) {
    return new NsecSigner(hexToBytes(hex))
  }

  static generate() {
    return new NsecSigner(generateSecretKey())
  }

  getPublicKey() {
    return getPublicKey(this.secretKey)
  }

  signEvent(template) {
    return finalizeEvent(template, this.secretKey)
  }

  canEncrypt() {
    return true
  }

  nip44Encrypt(peerPubkey, plaintext) {
    return encrypt(plaintext, conversationKey(this.secretKey, peerPubkey))
  }

  nip44Decrypt(peerPubkey, payload) {
    return decrypt(payload, conversationKey(this.secretKey, peerPubkey))
  }

  // Zero the key bytes after a one-shot use (the pasted-nsec sign-in path discards the key).
  dispose() {
    this.secretKey.fill(0)
  }
}

// A NIP-07 browser-extension signer (window.nostr). The key stays in the extension; every op
// delegates to it. nip44 is OPTIONAL in NIP-07, so canEncrypt feature-detects it.
export class Nip07Signer {
  constructor(provider = (typeof window !== "undefined" ? window.nostr : null)) {
    this.provider = provider
  }

  static available() {
    return typeof window !== "undefined" && !!window.nostr
  }

  getPublicKey() {
    return withTimeout(this.provider.getPublicKey(), "get your public key", NIP07_TIMEOUT_MS)
  }

  // A hung/unresponsive extension would otherwise leave the caller spinning forever; the bound is
  // generous so it never cuts off a user deliberating over the approval prompt.
  signEvent(template) {
    return withTimeout(this.provider.signEvent(template), "sign the event", NIP07_TIMEOUT_MS)
  }

  canEncrypt() {
    return !!(this.provider && this.provider.nip44 && typeof this.provider.nip44.encrypt === "function")
  }

  nip44Encrypt(peerPubkey, plaintext) {
    return withTimeout(this.provider.nip44.encrypt(peerPubkey, plaintext), "encrypt the message", NIP07_TIMEOUT_MS)
  }

  nip44Decrypt(peerPubkey, payload) {
    return withTimeout(this.provider.nip44.decrypt(peerPubkey, payload), "decrypt the message", NIP07_TIMEOUT_MS)
  }
}

// No signer op should hang the UI forever: nostr-tools' BunkerSigner has no per-request timeout, and a
// browser extension can stall. Cap each op so the UI can recover. Three bounds by intent: ongoing bunker
// ops get 30s; NIP-07 gets a generous 120s (the user may be deliberating over the extension prompt); the
// initial bunker connect gets a tight 10s because a dead relay/bunker should fail fast, not spin (it is
// disarmed the instant onauth fires, since from then on the wait is the user approving on their phone).
const BUNKER_TIMEOUT_MS = 30_000
const NIP07_TIMEOUT_MS = 120_000
const INTERACTIVE_TIMEOUT_MS = 10_000

// `armed` (optional) is polled when the timer fires; returning false cancels the rejection, so an
// onauth-gated handshake can run unbounded while the user approves. Per-request callers omit it.
function withTimeout(promise, action, ms = BUNKER_TIMEOUT_MS, armed = null) {
  let timer
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      if (armed && !armed()) return // disarmed (e.g. onauth fired): let the underlying promise settle
      reject(new Error(`Your signer did not respond in time to ${action}.`))
    }, ms)
  })
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => clearTimeout(timer))
}

// A stalled ONGOING bunker op (a previously-working remote signer that goes offline or whose grant is
// revoked) is a distinct, recoverable condition from a wrong-key signer. A typed error carries an honest,
// actionable message so call sites can tell "unreachable/revoked" from "controls a different key".
export class BunkerUnreachableError extends Error {
  constructor() {
    super("Your remote signer is unreachable; it may have been revoked or gone offline. Sign in again to reconnect.")
    this.name = "BunkerUnreachableError"
  }
}

function withBunkerTimeout(promise) {
  let timer
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new BunkerUnreachableError()), BUNKER_TIMEOUT_MS)
  })
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => clearTimeout(timer))
}

// A NIP-46 remote-signer ("bunker") session. The user's key stays in the bunker; ops are relay
// round-trips. Authorization is bound to the LOCAL CLIENT KEY (the first arg to fromBunker), not to the
// connection, so reusing one persisted client key lets a later session reconnect WITHOUT re-approval:
// pair() is the first-time handshake (generates + keeps the client key, returns a descriptor to
// persist); restore() rebuilds from that descriptor and skips connect(). nostr-tools is lazy-imported.
export class Nip46Signer {
  // descriptor: { clientSk: hex, pubkey, relays } -- the non-secret reconnect tuple the store persists.
  constructor(bunker, descriptor) {
    this.bunker = bunker
    this.descriptor = descriptor
  }

  // First-time pairing: generate the client key ONCE, connect (fires onauth for approval). The returned
  // signer's descriptor must be persisted so subsequent sessions reconnect silently.
  static async pair(input, { onauth } = {}) {
    const { BunkerSigner, parseBunkerInput } = await import("nostr-tools/nip46")
    const { generateSecretKey } = await import("nostr-tools/pure")
    const pointer = await parseBunkerInput(input)
    if (!pointer) throw new Error("invalid bunker URL")

    const clientSecretKey = generateSecretKey()
    // Disarm the tight connect bound once the bunker asks for approval: nostr-tools does not resolve
    // connect() on auth_url, so from here the wait is the user approving on their phone, not the network.
    let interactive = true
    const gatedOnauth = (url) => { interactive = false; onauth?.(url) }
    const bunker = BunkerSigner.fromBunker(clientSecretKey, pointer, { onauth: gatedOnauth })
    try {
      await withTimeout(bunker.connect(), "connect to your signer", INTERACTIVE_TIMEOUT_MS, () => interactive)
    } catch (error) {
      await bunker.close?.() // don't leak the bunker session if the connection fails
      throw error
    }
    const descriptor = { clientSk: bytesToHex(clientSecretKey), pubkey: pointer.pubkey, relays: pointer.relays }
    return new Nip46Signer(bunker, descriptor)
  }

  // Reconnect from a persisted descriptor by REUSING the same client key: the bunker recognizes the
  // already-authorized client, so there is NO connect() handshake and NO re-approval. fromBunker opens
  // the relay subscription itself. If the bunker re-prompts (onauth fires), the grant was revoked.
  static async restore({ clientSk, pubkey, relays }, { onauth } = {}) {
    const { BunkerSigner } = await import("nostr-tools/nip46")
    const bunker = BunkerSigner.fromBunker(hexToBytes(clientSk), { pubkey, relays, secret: "" }, { onauth })
    return new Nip46Signer(bunker, { clientSk, pubkey, relays })
  }

  getPublicKey() {
    return withBunkerTimeout(this.bunker.getPublicKey())
  }

  signEvent(template) {
    return withBunkerTimeout(this.bunker.signEvent(template))
  }

  // The BunkerSigner exposes nip44 (verified API), so structurally this signer can encrypt; whether
  // the REMOTE bunker GRANTS the nip44 permission is runtime-only, confirmed by a round-trip
  // self-test before first use. A bunker that lacks the grant throws on the first encrypt.
  canEncrypt() {
    return true
  }

  nip44Encrypt(peerPubkey, plaintext) {
    return withBunkerTimeout(this.bunker.nip44Encrypt(peerPubkey, plaintext))
  }

  nip44Decrypt(peerPubkey, payload) {
    return withBunkerTimeout(this.bunker.nip44Decrypt(peerPubkey, payload))
  }

  close() {
    return this.bunker.close?.()
  }
}

function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
}

function hexToBytes(hex) {
  if (typeof hex !== "string" || hex.length === 0 || hex.length % 2 !== 0) throw new Error("invalid hex key")
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return bytes
}
