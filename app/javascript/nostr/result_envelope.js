import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"

// The delivered result over NIP-17 (encrypted, order-scoped): the PROVIDER seals the finished work to the
// consumer so they can verify it before releasing the escrow. The mirror of order_envelope.js, reversed in
// direction (the provider authors; the consumer is the trust anchor). Gift-wrapped to the consumer with a
// provider self-copy; everything is end-to-end encrypted and the Rails runtime never sees the result
// (brief sec 6.3). Wire: a kind-14 rumor, subject "switchboard-result", joined to the listing by an `a`
// tag, content = JSON { v, orderId, result, attachments, note }. attachments are references only (url +
// content hash), never inline bytes.
//
// TRUST: a gift wrap proves only WHO sealed it (unwrap binds rumor.pubkey == seal.pubkey), not that they
// are the order's provider. Anyone can gift-wrap the consumer a forged result, so the caller MUST verify
// `from` equals the order's known provider pubkey before trusting an envelope.

const SUBJECT = "switchboard-result"
const VERSION = 1
const FETCH_TIMEOUT = 4000

// Seal a delivered result { orderId, coordinate, result, attachments, note } to the consumer. result is
// text/markdown; attachments are [{ url, hash, name, mime }] references. Throws unless it reaches a relay.
export async function sendResultEnvelope({ signer, ownPubkey, peerPubkey, relays, orderId, coordinate, result = "", attachments = [], note = "" }) {
  const content = JSON.stringify({ v: VERSION, orderId, result, attachments, note })
  const extraTags = coordinate ? [ [ "a", coordinate ] ] : []
  const rumor = buildRumor({ authorPubkey: ownPubkey, content, recipients: [ peerPubkey ], subject: SUBJECT, extraTags })
  const { toRecipient, toSelf } = await wrapMessage(rumor, signer, peerPubkey)
  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(toRecipient)
    // ok = acked; timeout = open + sent but slow to ack (possibly stored). Only hard errors everywhere fail.
    if (!results.some((result) => result.status === "ok" || result.status === "timeout")) throw new Error("delivered result did not reach any relay")
    await set.publishToMany(toSelf) // keep the provider's own copy, best-effort
  } finally {
    set.close()
  }
  return rumor
}

// Fetch + decrypt every delivered result addressed to me, newest-first. Each is
// { orderId, coordinate, result, attachments, note, from, createdAt }. Filters by the result subject (a
// relay's say-so is never trusted) and ignores wraps this signer cannot read or that are not result
// envelopes. The caller joins by orderId AND checks `from` against the order's provider before trusting it.
export async function fetchResultEnvelopes({ signer, ownPubkey, relays }) {
  const set = new RelaySet(relays, { signer })
  try {
    const results = []
    for (const wrap of await collectWraps(set, ownPubkey)) {
      const parsed = await readEnvelope(wrap, signer)
      if (parsed) results.push(parsed)
    }
    return results.sort((a, b) => b.createdAt - a.createdAt)
  } finally {
    set.close()
  }
}

// The latest delivered result for an order from a specific provider, or null. `provider` is REQUIRED: it is
// the trust anchor that rejects a result forged by anyone other than the order's actual provider.
export async function latestResultEnvelope({ signer, ownPubkey, relays, orderId, provider }) {
  const results = await fetchResultEnvelopes({ signer, ownPubkey, relays })
  return results.find((result) => result.orderId === orderId && result.from === provider) || null
}

// Decrypt one wrap into a result envelope, or null if it is unreadable / not a result / malformed.
async function readEnvelope(wrap, signer) {
  try {
    const rumor = await unwrap(wrap, signer)
    if (!rumor.tags.some(([ key, value ]) => key === "subject" && value === SUBJECT)) return null
    const body = JSON.parse(rumor.content)
    if (typeof body.orderId !== "string") return null
    const coordinate = (rumor.tags.find(([ key ]) => key === "a") || [])[1] || null
    return {
      orderId: body.orderId,
      coordinate,
      result: typeof body.result === "string" ? body.result : "",
      attachments: Array.isArray(body.attachments) ? body.attachments : [],
      note: typeof body.note === "string" ? body.note : "",
      from: rumor.pubkey,
      createdAt: rumor.created_at,
    }
  } catch {
    return null // a wrap this signer cannot read, or content that is not a JSON result envelope
  }
}

function collectWraps(set, ownPubkey) {
  return new Promise((resolve) => {
    const wraps = []
    const sub = set.subscribeMany([ { kinds: [ Kind.GIFT_WRAP ], "#p": [ ownPubkey ] } ], {
      onevent: (event) => wraps.push(event),
      oneose: () => { sub.close(); resolve(wraps) },
    })
    setTimeout(() => { sub.close(); resolve(wraps) }, FETCH_TIMEOUT)
  })
}
