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
// Slice 0 ships NsecSigner (a locally-held key: the pasted-nsec path and the test/interop signer).
// Nip07Signer / Nip46Signer arrive in Slice 0b, refactored out of nostr_auth_controller.js.

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
    return this.provider.getPublicKey()
  }

  signEvent(template) {
    return this.provider.signEvent(template)
  }

  canEncrypt() {
    return !!(this.provider && this.provider.nip44 && typeof this.provider.nip44.encrypt === "function")
  }

  nip44Encrypt(peerPubkey, plaintext) {
    return this.provider.nip44.encrypt(peerPubkey, plaintext)
  }

  nip44Decrypt(peerPubkey, payload) {
    return this.provider.nip44.decrypt(peerPubkey, payload)
  }
}

// A NIP-46 remote-signer ("bunker") session. The key stays in the bunker; ops are relay round-trips,
// so the connection is opened ONCE and held for the session (the one-shot sign-in path connects and
// closes per use). nostr-tools is lazy-imported so a page that never messages does not pull it.
export class Nip46Signer {
  constructor(bunker) {
    this.bunker = bunker
  }

  static async connect(input, { onauth } = {}) {
    const { BunkerSigner, parseBunkerInput } = await import("nostr-tools/nip46")
    const { generateSecretKey } = await import("nostr-tools/pure")
    const pointer = await parseBunkerInput(input)
    if (!pointer) throw new Error("invalid bunker URL")

    const bunker = BunkerSigner.fromBunker(generateSecretKey(), pointer, { onauth })
    try {
      await bunker.connect()
    } catch (error) {
      await bunker.close?.() // don't leak the bunker session if the connection fails
      throw error
    }
    return new Nip46Signer(bunker)
  }

  getPublicKey() {
    return this.bunker.getPublicKey()
  }

  signEvent(template) {
    return this.bunker.signEvent(template)
  }

  // The BunkerSigner exposes nip44 (verified API), so structurally this signer can encrypt; whether
  // the REMOTE bunker GRANTS the nip44 permission is runtime-only, confirmed by a round-trip
  // self-test before first use (Slice 2). A bunker that lacks the grant throws on the first encrypt.
  canEncrypt() {
    return true
  }

  nip44Encrypt(peerPubkey, plaintext) {
    return this.bunker.nip44Encrypt(peerPubkey, plaintext)
  }

  nip44Decrypt(peerPubkey, payload) {
    return this.bunker.nip44Decrypt(peerPubkey, payload)
  }

  close() {
    return this.bunker.close?.()
  }
}

function hexToBytes(hex) {
  if (typeof hex !== "string" || hex.length === 0 || hex.length % 2 !== 0) throw new Error("invalid hex key")
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return bytes
}
