import { sha256Hex } from "nostr/blossom"

// NIP-98 (kind 27235) HTTP auth, the per-request scheme the stateless Api controllers use (no cookie/CSRF).
// Signs an event binding the HTTP method, the SERVER-canonical absolute URL, and — for a body — its sha256,
// then returns the `Authorization` header. Two rules the server enforces (an opaque 401 otherwise):
//   - the `u` tag MUST be the server's canonical origin + path (config.x.canonical_origin), NOT a relative
//     path or window.location-derived URL; the caller passes the absolute URL the server rendered.
//   - the `payload` tag MUST be sha256-hex of the EXACT body bytes sent, so the body is serialized ONCE here
//     and reused for both the hash and the request (re-serializing could reorder keys and break the match).
// The event is signed by the LOGIN signer (NIP-07/46/nsec); the server matches its pubkey to the caller's
// identity. This is NOT the Cashu escrow key (that one co-signs proofs, never an HTTP auth event).

export async function nip98AuthHeader(signer, { url, method, body }) {
  const tags = [ [ "u", url ], [ "method", method ] ]
  if (body) tags.push([ "payload", await sha256Hex(new TextEncoder().encode(body)) ])

  const event = await signer.signEvent({ kind: 27235, created_at: nowSeconds(), tags, content: "" })

  return `Nostr ${btoa(JSON.stringify(event))}` // btoa emits standard padded base64 (server uses strict_decode64)
}

// fetch() with a NIP-98 Authorization header. `json` is serialized ONCE so the signed payload hash matches
// the bytes actually sent. Returns the raw Response; the caller checks res.ok and parses.
export async function nip98Fetch(url, { signer, method = "POST", json } = {}) {
  const body = json === undefined ? undefined : JSON.stringify(json)
  const headers = { Authorization: await nip98AuthHeader(signer, { url, method, body }) }
  if (body !== undefined) headers["Content-Type"] = "application/json"

  return fetch(url, { method, headers, body })
}

function nowSeconds() {
  return Math.floor(Date.now() / 1000)
}
