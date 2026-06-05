import { useWebSocketImplementation } from "nostr-tools/relay"

// TEST-ONLY in-page mock relay. Reproduces the NIP-01/42 wire frames a real relay sends so the real
// nostr-tools Relay (and our RelaySet over it) can be exercised deterministically and offline. Loaded
// only via the test bridge (test_support.js); nothing in the app imports it. Installed by swapping
// nostr-tools' WebSocket for FakeWebSocket via useWebSocketImplementation.

const servers = new Map() // normalized url -> MockRelayServer

// nostr-tools normalizes a host-only wss URL to include a trailing slash ("wss://a.test" becomes
// "wss://a.test/" via WHATWG URL serialization, even though normalizeURL strips the pathname), so key
// servers by a slash-stripped form and look them up the same way.
function norm(url) {
  return url.replace(/\/+$/, "")
}

class MockRelayServer {
  constructor(url, { authRequired = false, fail = false, proactiveAuth = true } = {}) {
    this.url = url
    this.authRequired = authRequired
    this.fail = fail                   // simulate a relay that never connects (onerror)
    this.proactiveAuth = proactiveAuth // false = challenge only reactively on REQ/EVENT (exercises re-subscribe)
    this.events = []                   // stored events
    this.sockets = new Set()           // connected FakeWebSockets
  }

  store(event) {
    if (!this.events.some((e) => e.id === event.id)) this.events.push(event)
  }

  broadcast(event) {
    for (const socket of this.sockets) socket.deliver(event)
  }
}

// Minimal filter match: kinds + single-letter tag filters (#p etc.), enough for kind-1059 #p inbox subs.
function matches(filter, event) {
  if (filter.kinds && !filter.kinds.includes(event.kind)) return false
  for (const key of Object.keys(filter)) {
    if (key[0] !== "#") continue
    const tag = key.slice(1)
    const wanted = filter[key]
    if (!event.tags.some(([t, v]) => t === tag && wanted.includes(v))) return false
  }
  return true
}

class FakeWebSocket {
  static OPEN = 1

  constructor(url) {
    this.url = url
    this.readyState = 0
    this.server = servers.get(norm(url))
    this.authed = false
    this.subs = new Map() // subid -> filters
    setTimeout(() => this.open(), 0)
  }

  open() {
    if (this.readyState !== 0) return
    if (this.server?.fail) { this.readyState = 3; this.onerror?.(); return } // a relay that refuses to connect
    this.readyState = FakeWebSocket.OPEN
    this.server?.sockets.add(this)
    this.onopen?.()
    if (this.server?.authRequired && this.server.proactiveAuth) this.emit([ "AUTH", this.challenge() ]) // challenge on connect
  }

  challenge() {
    return `challenge-${this.url}`
  }

  send(raw) {
    let message
    try { message = JSON.parse(raw) } catch { return }
    const [ type ] = message
    if (type === "EVENT") this.onClientEvent(message[1])
    else if (type === "REQ") this.onClientReq(message[1], message.slice(2))
    else if (type === "AUTH") this.onClientAuth(message[1])
    else if (type === "CLOSE") this.subs.delete(message[1])
  }

  onClientEvent(event) {
    if (this.server?.authRequired && !this.authed) {
      this.emit([ "OK", event.id, false, "auth-required: authentication required to publish" ])
      this.emit([ "AUTH", this.challenge() ])
      return
    }
    this.server?.store(event)
    this.emit([ "OK", event.id, true, "" ])
    this.server?.broadcast(event)
  }

  onClientReq(subid, filters) {
    if (this.server?.authRequired && !this.authed) {
      this.emit([ "CLOSED", subid, "auth-required: authentication required to read" ])
      this.emit([ "AUTH", this.challenge() ])
      return
    }
    this.subs.set(subid, filters)
    for (const event of this.server?.events || []) {
      if (filters.some((f) => matches(f, event))) this.emit([ "EVENT", subid, event ])
    }
    this.emit([ "EOSE", subid ])
  }

  // Accept any kind-22242 the client signs; a real relay verifies it, which nostr-tools' signer did.
  onClientAuth(authEvent) {
    this.authed = true
    this.emit([ "OK", authEvent.id, true, "" ])
  }

  // A live event published elsewhere on this server: push it to each matching open subscription.
  deliver(event) {
    for (const [ subid, filters ] of this.subs) {
      if (filters.some((f) => matches(f, event))) this.emit([ "EVENT", subid, event ])
    }
  }

  emit(frame) {
    setTimeout(() => { if (this.readyState === FakeWebSocket.OPEN) this.onmessage?.({ data: JSON.stringify(frame) }) }, 0)
  }

  close() {
    this.readyState = 3
    this.server?.sockets.delete(this)
    setTimeout(() => this.onclose?.({}), 0)
  }
}

// Install the mock for a set of relays. configs: [{ url, authRequired, seed: [events] }]. Urls must be
// already-normalized (no trailing slash, no :443) so they match what nostr-tools hands the socket.
export function installMockRelays(configs) {
  servers.clear()
  for (const config of configs) {
    const server = new MockRelayServer(config.url, {
      authRequired: config.authRequired, fail: config.fail, proactiveAuth: config.proactiveAuth,
    })
    ;(config.seed || []).forEach((event) => server.store(event))
    servers.set(config.url, server)
  }
  useWebSocketImplementation(FakeWebSocket)
  return [ ...servers.values() ]
}
