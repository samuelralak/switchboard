import { RelaySet } from "nostr/relay_set"
import { buildRumor, wrapMessage, unwrap, Kind } from "nostr/nip17"
import { MAX_PLAINTEXT } from "nostr/nip44"

// The keyless NIP-17 DM engine: a signer + a RelaySet + the cold-start cache, with the DOM left to the
// Stimulus wrapper (dm_client_controller). Decrypted content stays in the browser and is never sent to
// Rails. Held for the session (ongoing decryption), so the signer must be long-lived, not a one-shot.
//
//   new DmClient({ signer, relays, inboxUrl, onMessage })
//   await start()                 subscribe to my inbox + replay the cold-start cache; throws if no relay opens
//   await send(peerPubkey, text)  dual-wrap, publish to relays, deposit the recipient copy
//   stop()                        close the subscription + relays

export class DmClient {
  constructor({ signer, relays, inboxUrl = null, onMessage = () => {} }) {
    this.signer = signer
    this.relays = new RelaySet(relays, { signer })
    this.inboxUrl = inboxUrl
    this.onMessage = onMessage
    this.pubkey = null
    this.seen = new Set() // decrypted rumor ids, deduped across live + cold-start + own self-copy
    this.subscription = null
  }

  async start() {
    this.pubkey = await this.signer.getPublicKey()
    this.subscription = this.relays.subscribeMany(
      [ { kinds: [ Kind.GIFT_WRAP ], "#p": [ this.pubkey ] } ],
      { onevent: (wrap) => this.ingest(wrap) },
    )
    await this.coldStart()            // cache first -- works even if the relays are down
    await this.subscription.connected // then assert live connectivity (rejects if none open / none configured)
  }

  // Replay the recipient's Switchboard-controlled cache, following the keyset cursor across pages so a
  // backlog larger than one page is fully ingested (best-effort; relays are the source of truth).
  async coldStart() {
    if (!this.inboxUrl) return
    let cursor = null
    try {
      for (let page = 0; page < 100; page += 1) { // page cap backstops a misbehaving cursor
        const url = cursor ? `${this.inboxUrl}?cursor=${encodeURIComponent(cursor)}` : this.inboxUrl
        const response = await fetch(url, { headers: { Accept: "application/json" } })
        if (!response.ok) return // 401 = not signed in; treat any miss as empty
        const body = await response.json()
        for (const wrap of body.wraps || []) await this.ingest(wrap)
        cursor = body.cursor
        if (!cursor || (body.wraps || []).length === 0) return
      }
    } catch { /* a cache miss never blocks live delivery */ }
  }

  // Unwrap a gift wrap and surface the rumor once; a forged/garbage wrap (UnwrapError) is discarded.
  async ingest(wrap) {
    let rumor
    try {
      rumor = await unwrap(wrap, this.signer)
    } catch {
      return
    }
    if (this.seen.has(rumor.id)) return
    this.seen.add(rumor.id)
    this.onMessage(rumor)
  }

  async send(peerPubkey, content) {
    const rumor = buildRumor({ authorPubkey: this.pubkey, content, recipients: [ peerPubkey ] })
    if (byteLength(JSON.stringify(rumor)) > MAX_PLAINTEXT) throw new Error("message too long")

    let wrapped
    try {
      wrapped = await wrapMessage(rumor, this.signer, peerPubkey)
    } catch (error) {
      // the gift wrap re-encrypts the seal (which holds the rumor's ciphertext), so a payload under the
      // raw limit can still overflow the outer nip44 -- surface that as the same clean error, not a deep one.
      if (/exceeds|plaintext/i.test(error.message)) throw new Error("message too long")
      throw error
    }

    const { toRecipient, toSelf } = wrapped
    await Promise.all([ this.relays.publishToMany(toRecipient), this.relays.publishToMany(toSelf) ])
    await this.deposit(toRecipient) // anonymous cold-start copy for the recipient
    await this.ingest(toSelf)       // show my own message now (it also returns via the subscription)
    return rumor
  }

  // Anonymous deposit to the cold-start cache. Delivery already happened over relays, so any failure
  // (422 invalid, 507 full, network) is swallowed -- the cache is strictly best-effort.
  async deposit(wrap) {
    if (!this.inboxUrl) return
    try {
      await fetch(this.inboxUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrap),
      })
    } catch { /* best-effort */ }
  }

  stop() {
    this.subscription?.close()
    this.relays.close()
    this.seen.clear()
  }
}

// Capability self-test: a signer can message only if it actually round-trips NIP-44 to itself. Covers
// NIP-07 providers without nip44 (canEncrypt false) AND NIP-46 bunkers that expose nip44 but have not
// been granted the permission (canEncrypt true, but the encrypt throws at runtime).
export async function canMessage(signer) {
  if (!signer.canEncrypt()) return false
  try {
    const me = await signer.getPublicKey()
    const probe = "switchboard-capability-probe"
    const payload = await signer.nip44Encrypt(me, probe)
    return (await signer.nip44Decrypt(me, payload)) === probe
  } catch {
    return false
  }
}

function byteLength(text) {
  return new TextEncoder().encode(text).length
}
