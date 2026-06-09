import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"

// The order request over NIP-17 (encrypted, order-scoped): the consumer seals the filled service inputs
// (and an optional note) to the provider so the work can begin. Gift-wrapped to the provider with a
// self-copy; everything is end-to-end encrypted and the Rails runtime never sees the request content
// (brief sec 6.3). This is the order-envelope microstandard: a kind-14 rumor carrying a JSON body, joined
// to the listing by an `a` tag, namespaced by the "switchboard-order" subject.
//
// TRUST: a gift wrap proves only WHO sealed it (unwrap binds rumor.pubkey == seal.pubkey), not that they
// own the order. Anyone can gift-wrap the provider a forged envelope, so the caller MUST verify `from`
// equals the order's known consumer pubkey before trusting an envelope (the messages page does this).

const SUBJECT = "switchboard-order"
const VERSION = 1
const FETCH_TIMEOUT = 4000

// Seal an order request { orderId, coordinate, inputs, note } to the provider. inputs is the filled schema
// as [{ label, value }]. Throws unless it reaches a relay.
export async function sendOrderRequest({ signer, ownPubkey, peerPubkey, relays, orderId, coordinate, inputs = [], note = "" }) {
  const content = JSON.stringify({ v: VERSION, orderId, inputs, note })
  const extraTags = coordinate ? [ [ "a", coordinate ] ] : []
  const rumor = buildRumor({ authorPubkey: ownPubkey, content, recipients: [ peerPubkey ], subject: SUBJECT, extraTags })
  const { toRecipient, toSelf } = await wrapMessage(rumor, signer, peerPubkey)
  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(toRecipient)
    // ok = acked; timeout = open + sent but slow to ack (possibly stored). Only hard errors everywhere fail.
    if (!results.some((result) => result.status === "ok" || result.status === "timeout")) throw new Error("order request did not reach any relay")
    await set.publishToMany(toSelf) // keep the consumer's own copy, best-effort
  } finally {
    set.close()
  }
  return rumor
}

// Fetch + decrypt every order request addressed to me, newest-first. Each is
// { orderId, coordinate, inputs, note, from, createdAt }. Filters by the order subject (a relay's say-so
// is never trusted) and ignores wraps this signer cannot read or that are not order envelopes. The caller
// joins by orderId AND checks `from` against the order's consumer before trusting the content.
export async function fetchOrderRequests({ signer, ownPubkey, relays }) {
  const set = new RelaySet(relays, { signer })
  try {
    const requests = []
    for (const wrap of await collectWraps(set, ownPubkey)) {
      const parsed = await readEnvelope(wrap, signer)
      if (parsed) requests.push(parsed)
    }
    return requests.sort((a, b) => b.createdAt - a.createdAt)
  } finally {
    set.close()
  }
}

// The latest order request for an order from a specific consumer, or null. `consumer` is REQUIRED: it is
// the trust anchor that rejects an envelope forged by anyone other than the order's actual consumer.
export async function latestOrderRequest({ signer, ownPubkey, relays, orderId, consumer }) {
  const requests = await fetchOrderRequests({ signer, ownPubkey, relays })
  return requests.find((request) => request.orderId === orderId && request.from === consumer) || null
}

// Decrypt one wrap into an order envelope, or null if it is unreadable / not an order request / malformed.
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
      inputs: Array.isArray(body.inputs) ? body.inputs : [],
      note: typeof body.note === "string" ? body.note : "",
      from: rumor.pubkey,
      createdAt: rumor.created_at,
    }
  } catch {
    return null // a wrap this signer cannot read, or content that is not a JSON order envelope
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
