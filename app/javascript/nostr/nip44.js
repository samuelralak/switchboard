import { getConversationKey, encrypt as encryptV2, decrypt as decryptV2 } from "nostr-tools/nip44"

// The Ruby spine (lib/nip44.rb) uses a u16 length prefix, so a payload whose plaintext exceeds 65535
// bytes is unreadable server-side. Cap the browser to match until kind-15 file messages need more.
export const MAX_PLAINTEXT = 65535

// NIP-44 v2 conversation key: ECDH(secretKey, peerPubkey) -> HKDF-extract. Byte-identical to the Ruby
// spine; the browser and server derive the same key for the same pair.
export function conversationKey(secretKey, peerPubkey) {
  return getConversationKey(secretKey, peerPubkey)
}

export function encrypt(plaintext, conversationKey) {
  if (byteLength(plaintext) > MAX_PLAINTEXT) throw new Error("nip44: plaintext exceeds 65535 bytes")
  return encryptV2(plaintext, conversationKey)
}

export function decrypt(payload, conversationKey) {
  return decryptV2(payload, conversationKey)
}

function byteLength(text) {
  return new TextEncoder().encode(text).length
}
