import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"

// The escrow handshake over NIP-17 (encrypted, order-scoped): the consumer delivers the locked proofs
// to the provider ("token-delivery") and later reveals the preimage on approval ("preimage-reveal").
// Gift-wrapped to the counterparty; the sender keeps a self-copy. Everything is end-to-end encrypted;
// the Rails runtime never sees the token or preimage (brief sec 6.3).

const SUBJECT = "switchboard-escrow"
const FETCH_TIMEOUT = 4000

// Send a typed escrow message {orderId, type, data} to the counterparty. Throws unless it reaches a relay.
export async function sendEscrowMessage({ signer, ownPubkey, peerPubkey, relays, orderId, type, data }) {
  const content = JSON.stringify({ orderId, type, data })
  const rumor = buildRumor({ authorPubkey: ownPubkey, content, recipients: [ peerPubkey ], subject: SUBJECT })
  const { toRecipient, toSelf } = await wrapMessage(rumor, signer, peerPubkey)
  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(toRecipient)
    if (!results.some((result) => result.status === "ok")) throw new Error("escrow message did not reach any relay")
    await set.publishToMany(toSelf) // keep the sender's own copy, best-effort
  } finally {
    set.close()
  }
  return rumor
}

// Fetch + decrypt the escrow messages for an order addressed to me, oldest-first. Each is
// { from, type, data, createdAt }. Filters by the escrow subject AND the order id (a relay's say-so is
// never trusted), and ignores wraps this signer cannot read.
export async function fetchEscrowMessages({ signer, ownPubkey, relays, orderId }) {
  const set = new RelaySet(relays, { signer })
  try {
    const messages = []
    for (const wrap of await collectWraps(set, ownPubkey)) {
      try {
        const rumor = await unwrap(wrap, signer)
        if (!rumor.tags.some(([ key, value ]) => key === "subject" && value === SUBJECT)) continue
        const body = JSON.parse(rumor.content)
        if (body.orderId !== orderId) continue
        messages.push({ from: rumor.pubkey, type: body.type, data: body.data, createdAt: rumor.created_at })
      } catch {
        // skip a wrap this signer cannot read or that is not a JSON escrow message
      }
    }
    return messages.sort((a, b) => a.createdAt - b.createdAt)
  } finally {
    set.close()
  }
}

// The latest escrow message of a given type from a given sender for the order, or null.
export async function latestEscrowMessage({ signer, ownPubkey, relays, orderId, type, from }) {
  const messages = await fetchEscrowMessages({ signer, ownPubkey, relays, orderId })
  const matches = messages.filter((message) => message.type === type && (!from || message.from === from))
  return matches.length ? matches[matches.length - 1] : null
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
