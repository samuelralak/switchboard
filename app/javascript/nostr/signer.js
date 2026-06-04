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
}

function hexToBytes(hex) {
  if (typeof hex !== "string" || hex.length === 0 || hex.length % 2 !== 0) throw new Error("invalid hex key")
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return bytes
}
