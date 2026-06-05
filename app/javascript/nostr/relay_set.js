import { Relay } from "nostr-tools/relay"

// A thin manager over nostr-tools' low-level Relay (not SimplePool): connect lazily, publish to many
// relays with a bounded NIP-42 auth-required retry, and subscribe across many with cross-relay dedup,
// a single aggregate EOSE, and an honest readiness signal. The Relay hands a kind-22242 template to our
// user signer for AUTH and never sees a key (the whole reason for the low-level Relay). verifyEvent is
// left at nostr-tools' real Schnorr check -- NEVER overridden, or a forged kind-1059 would be accepted.
//
//   new RelaySet(urls, { signer })   signer answers NIP-42 challenges; optional for open relays
//   await publishToMany(event)       -> [{ url, status: "ok"|"error", reason }]
//   subscribeMany(filters, { onevent, oneose }) -> { close(), connected }  (connected rejects if none open)
//   close()                          tear down every relay

const CONNECT_TIMEOUT = 10000 // a dead relay must not hang connect() forever (nostr-tools sets none)
const AUTH_TIMEOUT = 5000     // a signer that throws mid-AUTH leaves authPromise pending forever; bound it

export class RelaySet {
  constructor(urls, { signer = null } = {}) {
    this.urls = [...new Set(urls)]
    this.signer = signer
    this.connections = new Map() // url -> Promise<Relay>
    this.relays = new Map()      // url -> Relay (for teardown)
    this.seen = new Set()        // event ids seen across all relays (cross-relay dedup)
  }

  // The callback the Relay calls for NIP-42: it builds the kind-22242 template, our signer signs it.
  authFn() {
    return this.signer ? (template) => this.signer.signEvent(template) : undefined
  }

  // Connect once per url; cache the in-flight promise so concurrent callers share one socket. Bounded by
  // a connect timeout, and a failed/timed-out connect is evicted (and its half-open socket closed) so a
  // later call can retry.
  relayFor(url) {
    let ready = this.connections.get(url)
    if (ready) return ready

    const relay = new Relay(url)
    const fn = this.authFn()
    if (fn) relay.onauth = fn // auto-authenticate whenever the relay sends a challenge
    this.relays.set(url, relay)
    ready = Promise.race([
      relay.connect().then(() => relay),
      sleep(CONNECT_TIMEOUT).then(() => { throw new Error(`connect timed out: ${url}`) }),
    ]).catch((error) => {
      this.connections.delete(url)
      if (relay.ws && relay.ws.readyState === 0) {
        try { relay.ws.close() } catch { /* nostr-tools' close() only acts on OPEN, so close the ws directly */ }
      }
      throw error
    })
    this.connections.set(url, ready)
    return ready
  }

  async publishToMany(event) {
    return Promise.all(this.urls.map((url) => this.publishOne(url, event)))
  }

  async publishOne(url, event) {
    try {
      const relay = await this.relayFor(url)
      try {
        return { url, status: "ok", reason: await relay.publish(event) }
      } catch (error) {
        if (!this.signer || !/auth-required/i.test(error.message)) throw error
        await this.settleAuth(relay)
        return { url, status: "ok", reason: await relay.publish(event) } // single retry after auth
      }
    } catch (error) {
      return { url, status: "error", reason: error.message }
    }
  }

  // Wait for the relay's auto-auth (onauth) to finish, or drive it if a challenge is present but onauth
  // has not fired yet. Bounded twice: a short poll for the challenge to arrive, then a race with a
  // timeout -- nostr-tools' auth() never rejects when the signer throws (it only console.warns), so an
  // unbounded await would hang the publish forever.
  async settleAuth(relay) {
    for (let i = 0; i < 100 && !relay.authPromise && !relay.challenge; i++) await sleep(10)
    const deadline = sleep(AUTH_TIMEOUT)
    if (relay.authPromise) return Promise.race([relay.authPromise.catch(() => {}), deadline])
    if (relay.challenge && this.signer) return Promise.race([relay.auth(this.authFn()).catch(() => {}), deadline])
  }

  // Subscribe across all relays. Cross-relay dedup via the shared seen-Set (the alreadyHaveEvent hook
  // skips an id already delivered by another relay); oneose fires once, on the first relay to reach
  // end-of-stored-events; an auth-required CLOSED re-subscribes once after authenticating. `connected`
  // resolves on the first relay to subscribe and rejects if every relay fails (or none are configured),
  // so callers can show honest connectivity instead of a silent false positive.
  subscribeMany(filters, { onevent, oneose } = {}) {
    const subs = []
    let eosed = false
    let settled = false
    let failures = 0
    let resolveReady
    let rejectReady
    const connected = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject })
    if (this.urls.length === 0) { settled = true; rejectReady(new Error("no relays configured")) }

    const open = (url, retried = false) => {
      this.relayFor(url).then((relay) => {
        const sub = relay.subscribe(filters, {
          alreadyHaveEvent: (id) => this.seen.has(id),
          receivedEvent: (_relay, id) => this.seen.add(id),
          onevent: (event) => onevent?.(event),
          oneose: () => { if (!eosed) { eosed = true; oneose?.() } },
          onclose: (reason) => {
            if (!retried && this.signer && /auth-required/i.test(String(reason))) {
              this.settleAuth(relay).then(() => open(url, true))
            }
          },
        })
        subs.push(sub)
        if (!settled) { settled = true; resolveReady() }
      }).catch(() => {
        failures += 1
        if (!settled && failures === this.urls.length) { settled = true; rejectReady(new Error("all relays failed")) }
      })
    }

    this.urls.forEach((url) => open(url))
    return { close: () => subs.forEach((sub) => { try { sub.close() } catch { /* already closed */ } }), connected }
  }

  close() {
    for (const relay of this.relays.values()) {
      try { relay.close() } catch { /* ignore */ }
    }
    this.connections.clear()
    this.relays.clear()
    this.seen.clear()
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
