import { verifyEvent, finalizeEvent, generateSecretKey } from "nostr-tools/pure"
import { eventId } from "nostr/canonical"
import { conversationKey, encrypt } from "nostr/nip44"

export const Kind = { SEAL: 13, CHAT: 14, FILE: 15, GIFT_WRAP: 1059 }
const RUMOR_FIELDS = ["id", "pubkey", "created_at", "kind", "tags", "content"]
const NUL = String.fromCharCode(0)
const TWO_DAYS = 2 * 24 * 60 * 60

export class UnwrapError extends Error {}

const nowSeconds = () => Math.floor(Date.now() / 1000)

// A unix timestamp randomized uniformly within the last two days, never in the future. Mirrors
// Messages::Actions::RandomPastTimestamp; called once per layer so seal and wrap draw independently.
function pastTimestamp() {
  const span = crypto.getRandomValues(new Uint32Array(1))[0] % (TWO_DAYS + 1)
  return nowSeconds() - span
}

// --- Send side -------------------------------------------------------------------------------------

// Build an UNSIGNED NIP-17 rumor (kind 14 chat by default) carrying an id but no sig. created_at is
// the real time; only seal and wrap are randomized. Mirrors Messages::BuildRumor. authorPubkey MUST
// be the signer's own pubkey (the anti-impersonation anchor).
export function buildRumor({ authorPubkey, content, recipients = [], replyTo = null, subject = null, extraTags = [], kind = Kind.CHAT, createdAt = nowSeconds() }) {
  const tags = recipients.map((pubkey) => ["p", pubkey])
  if (replyTo) tags.push(["e", replyTo])
  if (subject) tags.push(["subject", subject])
  for (const tag of extraTags) tags.push(tag) // e.g. an `a` tag joining the rumor to a listing coordinate
  const rumor = { pubkey: authorPubkey, created_at: createdAt, kind, tags, content }
  rumor.id = eventId(rumor)
  return rumor
}

// NIP-59 seal (kind 13): the rumor JSON nip44-encrypted to the recipient under the AUTHOR's key, then
// signed by the author's signer. Empty tags, past-randomized created_at. Mirrors Messages::Seal.
export async function seal(rumor, signer, recipientPubkey, createdAt = pastTimestamp()) {
  const content = await signer.nip44Encrypt(recipientPubkey, JSON.stringify(rumor))
  return signer.signEvent({ kind: Kind.SEAL, tags: [], content, created_at: createdAt })
}

// NIP-59 gift wrap (kind 1059): the seal JSON nip44-encrypted under a FRESH single-use ephemeral key
// and signed by it, p-tagged to the recipient, independently past-randomized. Mirrors Messages::GiftWrap.
export function giftWrap(sealedEvent, recipientPubkey, createdAt = pastTimestamp()) {
  const ephemeral = generateSecretKey()
  const content = encrypt(JSON.stringify(sealedEvent), conversationKey(ephemeral, recipientPubkey))
  return finalizeEvent({ kind: Kind.GIFT_WRAP, tags: [["p", recipientPubkey]], content, created_at: createdAt }, ephemeral)
}

// NIP-17 (line 97): wrap a message to the recipient AND back to the sender, so it appears in both
// inboxes. Each pubkey gets its own seal (encrypted to it) and its own ephemeral wrap.
export async function wrapMessage(rumor, signer, recipientPubkey) {
  const toRecipient = giftWrap(await seal(rumor, signer, recipientPubkey), recipientPubkey)
  const toSelf = giftWrap(await seal(rumor, signer, rumor.pubkey), rumor.pubkey)
  return { toRecipient, toSelf }
}

// --- Receive side ----------------------------------------------------------------------------------

// Reverse a NIP-59 gift wrap with the recipient's signer and return the validated rumor (the six
// canonical fields only). Mirrors app/services/messages/unwrap.rb exactly, so a browser-decrypted
// message and a Ruby-decrypted one agree:
//   * wrap (1059) and seal (13) are SIGNED -> full NIP-01 verify (id + sig), then a kind gate;
//   * the seal's tags MUST be empty;
//   * the rumor is UNSIGNED -> validated directly (NIP-01 typing, a recomputed id, no sig, no NUL);
//   * seal.pubkey === rumor.pubkey, or any sender could forge authorship (NIP-17 anti-impersonation).
// Throws UnwrapError on any violation; the caller discards the wrap.
export async function unwrap(giftWrapEvent, signer) {
  const wrap = verifySigned(giftWrapEvent, Kind.GIFT_WRAP, "gift wrap")
  const sealedEvent = verifySigned(await decryptLayer(signer, wrap.pubkey, wrap.content), Kind.SEAL, "seal")
  if (!Array.isArray(sealedEvent.tags) || sealedEvent.tags.length !== 0) throw new UnwrapError("seal tags must be empty")

  return validatedRumor(await decryptLayer(signer, sealedEvent.pubkey, sealedEvent.content), sealedEvent)
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

function validatedRumor(rumor, sealedEvent) {
  assertTyped(rumor)
  if ("sig" in rumor) throw new UnwrapError("rumor must be unsigned")
  if (containsNullByte(rumor)) throw new UnwrapError("rumor contains null bytes")
  if (eventId(rumor) !== rumor.id) throw new UnwrapError("rumor id mismatch")
  if (sealedEvent.pubkey !== rumor.pubkey) throw new UnwrapError("impersonation: seal.pubkey != rumor.pubkey")

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
