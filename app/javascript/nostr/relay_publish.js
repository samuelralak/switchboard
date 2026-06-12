import { RelaySet } from "nostr/relay_set"
import { normalizeRelayUrl } from "nostr/relay_url"

// Assembles, signs, and broadcasts a kind-10002 (NIP-65 relay list) non-custodially. A kind-10002 is
// REPLACEABLE (one per pubkey, no d-tag), and a new one REPLACES the old wholesale, so the form holds the
// FULL set of relays and this rebuilds every r-tag from it (unlike the profile editor, there is nothing to
// merge: NIP-65 carries only r-tags + an empty content). The r-tag marker contract MUST match the server
// parser (Users::RelayListUpsert#row_for): an unmarked r-tag is read AND write; a "read"/"write" marker
// restricts it. A row with neither read nor write is dropped (the parser would reject it).
const RELAY_LIST = 10002 // NIP-65

// Build the kind-10002 template from the form's relay rows ([{ url, read, write }]). Each url is canonicalized
// (so the r-tags match the server's stored form) and deduped on that canonical url (the last row for a url
// wins), so casing/trailing-slash variants collapse to one tag rather than inflating the list past the cap.
export function buildRelayListEvent(rows) {
  const byUrl = new Map()
  for (const row of rows || []) {
    const url = normalizeRelayUrl(row.url)
    if (!url || (!row.read && !row.write)) continue
    byUrl.set(url, marker(row))
  }
  const tags = Array.from(byUrl, ([url, mark]) => (mark ? ["r", url, mark] : ["r", url]))
  return { kind: RELAY_LIST, created_at: Math.floor(Date.now() / 1000), content: "", tags }
}

// The NIP-65 marker for a row: omitted when both read+write, else the single restricting role.
function marker(row) {
  if (row.read && row.write) return null
  return row.read ? "read" : "write"
}

// Sign + broadcast the relay list. Returns the signed event, per-relay results, and how many accepted it.
export async function broadcastRelayList(rows, signer, relays) {
  const signed = await signer.signEvent(buildRelayListEvent(rows))
  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(signed)
    return { event: signed, results, reached: results.filter((r) => r.status === "ok").length }
  } finally {
    set.close()
  }
}
