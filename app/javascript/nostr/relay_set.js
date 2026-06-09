import { Relay } from "nostr-tools/relay"
import { BoundedSet } from "nostr/bounded_set"

// A thin manager over nostr-tools' low-level Relay (not SimplePool): connect lazily, publish to many
// relays with a bounded NIP-42 auth-required retry AND a per-relay timeout, and subscribe across many
// with cross-relay dedup, a single aggregate EOSE, drop-and-wake recovery, and a live connectivity
// signal. The Relay hands a kind-22242 template to our user signer for AUTH and never sees a key (the
// whole reason for the low-level Relay). verifyEvent is left at nostr-tools' real Schnorr check --
// NEVER overridden, or a forged kind-1059 would be accepted.
//
//   new RelaySet(urls, { signer })   signer answers NIP-42 challenges; optional for open relays
//   await publishToMany(event)       -> [{ url, status: "ok"|"timeout"|"error", reason }] (each relay bounded;
//                                       "timeout" = open + sent but no OK within PUBLISH_TIMEOUT, possibly delivered)
//   subscribeMany(filters, { onevent, oneose }) -> { close(), connected, addEventListener(...) }
//   close()                          tear down every relay
//
// The subscription handle is an event target: "relay-degraded" (a relay dropped, reconnecting),
// "relay-reopened" (a relay came back), "all-relays-closed" (none open). The DM UI reflects these so a
// silent inbox death becomes a visible "Reconnecting…" instead of a frozen "Connected".

const CONNECT_TIMEOUT = 10000  // a dead relay must not hang connect() forever (nostr-tools sets none)
const AUTH_TIMEOUT = 5000      // a signer that throws mid-AUTH leaves authPromise pending forever; bound it
const PUBLISH_TIMEOUT = 8000   // an open-but-unresponsive relay must not hang the whole Promise.all send
const RECONNECT_BASE = 1000    // first reconnect delay; doubles per consecutive failure
const RECONNECT_MAX = 30000    // backoff ceiling
const IDLE_PROBE_AFTER = 60000 // no frame for this long (tab visible) -> probe the socket for liveness
const PROBE_TIMEOUT = 8000     // a live relay answers a probe REQ with EOSE within this; else reconnect

export class RelaySet {
  constructor(urls, { signer = null, probeAfter = IDLE_PROBE_AFTER, probeTimeout = PROBE_TIMEOUT, publishTimeout = PUBLISH_TIMEOUT } = {}) {
    this.urls = [...new Set(urls)]
    this.signer = signer
    this.probeAfter = probeAfter         // ms of silence (tab visible) before a liveness probe (overridable in tests)
    this.probeTimeout = probeTimeout     // ms a live relay has to answer the probe before we treat it as dead
    this.publishTimeout = publishTimeout // ms a publish waits for OK before surfacing "timeout" (overridable in tests)
    this.connections = new Map() // url -> Promise<Relay>
    this.relays = new Map()      // url -> Relay (for teardown / cache eviction)
    this.seen = new BoundedSet() // event ids seen across all relays (cross-relay dedup)
    this.closed = false
  }

  // The callback the Relay calls for NIP-42: it builds the kind-22242 template, our signer signs it.
  authFn() {
    return this.signer ? (template) => this.signer.signEvent(template) : undefined
  }

  // Connect once per url; cache the in-flight promise so concurrent callers share one socket. Bounded by
  // a connect timeout; a failed/timed-out connect evicts the cache entry (and closes the half-open
  // socket) so a later call re-dials a fresh Relay.
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
      this.evict(url)
      throw error
    })
    this.connections.set(url, ready)
    return ready
  }

  // Drop a url's cached connection and close its socket so the next relayFor builds a fresh Relay.
  // WebSocket.close() is idempotent, so closing unconditionally is safe and never leaks a half-open socket.
  evict(url) {
    this.connections.delete(url)
    const relay = this.relays.get(url)
    if (!relay) return

    this.relays.delete(url)
    try { relay.close() } catch { /* ignore */ }
    try { relay.ws?.close() } catch { /* nostr-tools' close() only acts on OPEN; close the ws too */ }
  }

  async publishToMany(event) {
    return Promise.all(this.urls.map((url) => this.publishOne(url, event)))
  }

  async publishOne(url, event) {
    try {
      const relay = await this.relayFor(url)
      try {
        return await this.attempt(relay, event, url)
      } catch (error) {
        if (!this.signer || !/auth-required/i.test(error.message)) throw error

        await this.settleAuth(relay)
        return await this.attempt(relay, event, url) // single retry after auth -- SAME timeout-mapping as the first
      }
    } catch (error) {
      return { url, status: "error", reason: error.message }
    }
  }

  // One publish attempt. "timeout" is distinct from "error": the relay was OPEN and we sent the EVENT but no
  // OK arrived in time, so it MAY have stored it -- callers treat timeout as "possibly delivered". Both the
  // first attempt and the post-auth retry go through here so a post-auth timeout cannot drift to "error".
  // A non-timeout rejection (auth-required, or a relay OK:false) is re-thrown for publishOne to classify.
  async attempt(relay, event, url) {
    try {
      return { url, status: "ok", reason: await this.publishBounded(relay, event, url) }
    } catch (error) {
      if (/publish timed out/.test(error.message)) return { url, status: "timeout", reason: error.message }

      throw error
    }
  }

  // Bound one relay.publish: an open relay that never returns OK must not hang Promise.all and push the
  // caller into a duplicate publish on retry. A timeout surfaces as a distinct per-relay status, not a
  // stalled send. The losing relay.publish is swallowed so it cannot raise an unhandled rejection later.
  publishBounded(relay, event, url) {
    const live = relay.publish(event)
    live.catch(() => {})

    return Promise.race([
      live,
      sleep(this.publishTimeout).then(() => { throw new Error(`publish timed out: ${url}`) }),
    ])
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

  // Subscribe across all relays. Cross-relay dedup via the shared seen-set; oneose fires once on the first
  // relay to reach end-of-stored-events. Recovery: any non-user close evicts the dead socket and reconnects
  // with capped backoff (auth-required authenticates first); going online or foregrounding the tab
  // revalidates every relay; and a visible idle relay is probed and reconnected if it has gone silent.
  subscribeMany(filters, { onevent, oneose } = {}) {
    const events = new EventTarget()
    const subsByUrl = new Map()       // url -> live sub
    const retries = new Map()         // url -> consecutive reconnect count (backoff)
    const reconnectTimers = new Map() // url -> pending reconnect timer
    const everFailed = new Set()      // urls that failed their initial connect (for the connected verdict)
    const connectedOnce = new Set()   // urls that have connected before, so reopened is a real recovery
    const probing = new Set()         // urls with a probe in flight, so probes never overlap on one url
    const probeTimers = new Map()     // url -> probe deadline timer, so revalidate/close can cancel an in-flight probe
    let lastSeen = now()
    let eosed = false
    let settled = false
    let subClosed = false
    let resolveReady, rejectReady
    const connected = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject })
    if (this.urls.length === 0) { settled = true; rejectReady(new Error("no relays configured")) }

    const stopped = () => this.closed || subClosed
    const markSeen = () => { lastSeen = now() }
    const emit = (type, detail) => events.dispatchEvent(new CustomEvent(type, detail ? { detail } : undefined))

    // A failed (re)connect retries with capped, jittered backoff instead of giving up. One timer per url.
    const scheduleReconnect = (url) => {
      if (stopped() || reconnectTimers.has(url)) return

      const n = (retries.get(url) || 0) + 1
      retries.set(url, n)
      const delay = Math.min(RECONNECT_BASE * 2 ** (n - 1), RECONNECT_MAX) * (1 + Math.random() * 0.25)
      reconnectTimers.set(url, setTimeout(() => { reconnectTimers.delete(url); open(url) }, delay))
    }

    const open = (url, authRetry = false) => {
      this.relayFor(url).then((relay) => {
        if (stopped()) return

        const sub = relay.subscribe(filters, {
          alreadyHaveEvent: (id) => this.seen.has(id),
          receivedEvent: (_relay, id) => { this.seen.add(id); markSeen() },
          onevent: (event) => { markSeen(); onevent?.(event) },
          oneose: () => { markSeen(); if (!eosed) { eosed = true; oneose?.() } },
          onclose: (reason) => {
            subsByUrl.delete(url)
            if (stopped()) return

            // auth-required: authenticate once, then reopen immediately (no backoff, same socket).
            if (!authRetry && this.signer && /auth-required/i.test(String(reason))) {
              this.settleAuth(relay).then(() => { if (!stopped()) open(url, true) })
              return
            }

            this.evict(url) // the socket is dead: drop the cached promise so we re-dial a fresh one
            emit("relay-degraded", { url })
            if (subsByUrl.size === 0) emit("all-relays-closed")
            scheduleReconnect(url)
          },
        })
        subsByUrl.set(url, sub)
        retries.set(url, 0) // a clean (re)subscribe resets the backoff
        markSeen()
        if (!settled) { settled = true; resolveReady() }
        else if (connectedOnce.has(url)) emit("relay-reopened", { url }) // a real recovery, not a first connect

        connectedOnce.add(url)
      }).catch(() => {
        if (stopped()) return

        everFailed.add(url)
        if (!settled && everFailed.size >= this.urls.length) { settled = true; rejectReady(new Error("all relays failed")) }
        scheduleReconnect(url)
      })
    }

    // Revalidate every relay on wake/online: a half-open socket still reports OPEN, so reopen rather than
    // trust readyState. Only when the subscription is live.
    const revalidate = () => {
      if (stopped()) return

      for (const url of this.urls) {
        const sub = subsByUrl.get(url)
        // Detach onclose first: nostr-tools' close() fires it unconditionally, and this is a deliberate
        // reopen, not a drop -- running the drop path would flash a false "Connection lost" on a live inbox.
        if (sub) { sub.onclose = undefined; try { sub.close() } catch { /* already closed */ } }
        subsByUrl.delete(url)
        clearTimeout(reconnectTimers.get(url))
        reconnectTimers.delete(url)
        // Cancel an in-flight probe for this url: otherwise its deadline could fire after we reopen and tear
        // down the freshly-revalidated LIVE relay, flashing a false "Reconnecting…".
        clearTimeout(probeTimers.get(url))
        probeTimers.delete(url)
        probing.delete(url)
        this.evict(url)
        open(url)
      }
    }

    // Visible-only liveness probe: if no frame has arrived for probeAfter while the tab is visible, the
    // socket may be silently half-open. A quiet-but-alive relay still answers a probe REQ with EOSE; a
    // dead one does not, so we reconnect. Visibility-gated so a backgrounded tab never churns, and a
    // legitimately quiet inbox is left alone except for one cheap probe per idle window.
    const probe = () => {
      if (stopped() || hidden() || now() - lastSeen < this.probeAfter) return

      for (const [url, sub] of subsByUrl) {
        const relay = this.relays.get(url)
        if (!relay || probing.has(url)) continue // one probe per url at a time: never overlap deadlines

        probing.add(url)
        let answered = false
        let abandoned = false
        try {
          // eoseTimeout MUST outlast probeTimeout: nostr-tools fabricates an EOSE on its own (default
          // 4400ms) timer with no proof a frame arrived, which would falsely answer the probe. Pushing it
          // past our deadline means only a REAL wire EOSE from a live relay can set answered=true in time.
          const probeSub = relay.subscribe([{ ids: [ "0".repeat(64) ] }], {
            eoseTimeout: this.probeTimeout + 2000,
            oneose: () => {
              if (abandoned || stopped()) return // the orphaned eose timer must not refresh a closed probe

              answered = true
              markSeen()
              probing.delete(url)
              probeTimers.delete(url)
              try { probeSub.close() } catch { /* closed */ }
            },
          })
          const timer = setTimeout(() => {
            probing.delete(url)
            probeTimers.delete(url)
            if (answered || stopped()) return

            abandoned = true
            try { probeSub.close() } catch { /* closed */ }
            try { sub.close() } catch { /* closed */ } // dead socket: drive our onclose -> evict + reconnect
            this.evict(url)
            scheduleReconnect(url)
          }, this.probeTimeout)
          probeTimers.set(url, timer)
        } catch { probing.delete(url) /* relay already gone: the close path handles it */ }
      }
    }

    const onOnline = () => revalidate()
    const onVisible = () => { if (!hidden()) revalidate() }
    addGlobal("online", onOnline)
    addGlobal("visibilitychange", onVisible)
    const probeTimer = setInterval(probe, this.probeAfter / 2)

    this.urls.forEach((url) => open(url))

    return {
      connected,
      addEventListener: (...args) => events.addEventListener(...args),
      removeEventListener: (...args) => events.removeEventListener(...args),
      close: () => {
        subClosed = true
        clearInterval(probeTimer)
        removeGlobal("online", onOnline)
        removeGlobal("visibilitychange", onVisible)
        for (const timer of reconnectTimers.values()) clearTimeout(timer)
        reconnectTimers.clear()
        for (const timer of probeTimers.values()) clearTimeout(timer)
        probeTimers.clear()
        for (const sub of subsByUrl.values()) { try { sub.close() } catch { /* already closed */ } }
        subsByUrl.clear()
      },
    }
  }

  close() {
    this.closed = true
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

function now() {
  return Date.now()
}

function hidden() {
  return typeof document !== "undefined" && document.visibilityState === "hidden"
}

// online lives on window/globalThis; visibilitychange lives on document. Guarded so a non-DOM context
// (should not happen in the browser, but be safe) never throws.
function addGlobal(type, handler) {
  const target = type === "visibilitychange" ? globalThis.document : globalThis
  target?.addEventListener?.(type, handler)
}

function removeGlobal(type, handler) {
  const target = type === "visibilitychange" ? globalThis.document : globalThis
  target?.removeEventListener?.(type, handler)
}
