import { verifyEvent } from "nostr-tools/pure"
import { eventId } from "nostr/canonical"

export const Kind = { SEAL: 13, CHAT: 14, FILE: 15, GIFT_WRAP: 1059 }
const RUMOR_FIELDS = ["id", "pubkey", "created_at", "kind", "tags", "content"]
const NUL = String.fromCharCode(0)

export class UnwrapError extends Error {}

// Reverse a NIP-59 gift wrap with the recipient's signer and return the validated rumor (the six
// canonical fields only). Mirrors app/services/messages/unwrap.rb exactly, so a browser-decrypted
// message and a Ruby-decrypted one agree:
//   * wrap (1059) and seal (13) are SIGNED -> full NIP-01 verify (id + sig), then a kind gate;
//   * the seal's tags MUST be empty;
//   * the rumor is UNSIGNED -> validated directly (NIP-01 typing, a recomputed id, no sig, no NUL);
//   * seal.pubkey === rumor.pubkey, or any sender could forge authorship (NIP-17 anti-impersonation).
// Throws UnwrapError on any violation; the caller discards the wrap.
export async function unwrap(giftWrap, signer) {
  const wrap = verifySigned(giftWrap, Kind.GIFT_WRAP, "gift wrap")
  const seal = verifySigned(await decryptLayer(signer, wrap.pubkey, wrap.content), Kind.SEAL, "seal")
  if (!Array.isArray(seal.tags) || seal.tags.length !== 0) throw new UnwrapError("seal tags must be empty")

  return validatedRumor(await decryptLayer(signer, seal.pubkey, seal.content), seal)
}

// A signed layer (wrap or seal): full NIP-01 verification, then the kind gate.
function verifySigned(event, kind, label) {
  if (!event || typeof event !== "object") throw new UnwrapError(`${label}: not an object`)
  if (!verifyEvent(event)) throw new UnwrapError(`${label}: bad signature`)
  if (event.kind !== kind) throw new UnwrapError(`${label}: expected kind ${kind}`)
  return event
}

// nip44-decrypt one layer through the signer and parse the inner event. Never include the decrypted
// bytes or the underlying error in the thrown message -- that would leak plaintext to logs/UI.
async function decryptLayer(signer, peerPubkey, ciphertext) {
  let parsed
  try {
    parsed = JSON.parse(await signer.nip44Decrypt(peerPubkey, ciphertext))
  } catch {
    throw new UnwrapError("decrypt failed")
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new UnwrapError("decrypted layer is not an object")
  }
  return parsed
}

function validatedRumor(rumor, seal) {
  assertTyped(rumor)
  if ("sig" in rumor) throw new UnwrapError("rumor must be unsigned")
  if (containsNullByte(rumor)) throw new UnwrapError("rumor contains null bytes")
  if (eventId(rumor) !== rumor.id) throw new UnwrapError("rumor id mismatch")
  if (seal.pubkey !== rumor.pubkey) throw new UnwrapError("impersonation: seal.pubkey != rumor.pubkey")

  return pick(rumor, RUMOR_FIELDS)
}

// NIP-01 typing the signed layers get from verifyEvent but the unsigned rumor skips.
function assertTyped(rumor) {
  const strings = ["id", "pubkey", "content"].every((key) => typeof rumor[key] === "string")
  const integers = ["created_at", "kind"].every((key) => Number.isInteger(rumor[key]))
  if (!(strings && integers && Array.isArray(rumor.tags))) {
    throw new UnwrapError("rumor has malformed NIP-01 fields")
  }
}

function containsNullByte(node) {
  if (typeof node === "string") return node.includes(NUL)
  if (Array.isArray(node)) return node.some(containsNullByte)
  if (node && typeof node === "object") return Object.values(node).some(containsNullByte)
  return false
}

function pick(object, keys) {
  const out = {}
  for (const key of keys) if (key in object) out[key] = object[key]
  return out
}
