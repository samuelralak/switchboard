// Canonicalize a relay URL to the SAME form the server's Shared::NormalizeRelayUrl produces: lowercase
// scheme + host, the default ws/wss port dropped, and trailing slashes stripped. The browser and server must
// agree on one url per relay, so the kind-10002 carries canonical r-tags and the editor dedups exactly the
// way Users::RelayListUpsert projects. Returns null for an unusable url (non-ws scheme, no host, or embedded
// credentials), which the server would reject anyway. This canonicalizes ONLY; the server stays the authority
// on relay SAFETY (the anti-SSRF host check), so a hostile relay is dropped server-side on ingest, not here.
export function normalizeRelayUrl(raw) {
  let url
  try {
    url = new URL(String(raw == null ? "" : raw).trim())
  } catch {
    return null
  }

  const scheme = url.protocol.replace(/:$/, "").toLowerCase()
  if (scheme !== "ws" && scheme !== "wss") return null
  if (url.username || url.password) return null // no embedded credentials (matches the server)

  const host = url.hostname.toLowerCase()
  if (!host) return null

  const port = url.port ? `:${url.port}` : "" // the URL API already drops the default ws/wss port
  const path = url.pathname.replace(/\/+$/, "") // strip one-or-more trailing slashes ("/" -> "")
  return `${scheme}://${host}${port}${path}`
}
