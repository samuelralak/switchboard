import { RelaySet } from "nostr/relay_set"

// Assembles, signs, and broadcasts a kind-0 (NIP-01 profile metadata) non-custodially. A kind-0 is
// REPLACEABLE (one per pubkey, no d-tag), and a new one REPLACES the old wholesale -- so to avoid clobbering
// fields this form does not manage (custom keys, and NIP-39 identity tags), we MERGE the edited fields onto
// the user's existing kind-0 (content + tags) instead of starting from scratch.
const METADATA = 0

// Build the kind-0 template from the form `fields` and the existing `base` ({ content: <json string>, tags }).
// A non-empty field overwrites; an explicitly-blanked field is removed; every other key on the base content
// and every base tag survives.
export function buildProfileEvent(fields, base = {}) {
  const content = parseContent(base.content)
  for (const [key, value] of Object.entries(fields)) {
    const v = (value == null ? "" : String(value)).trim()
    if (v) content[key] = v
    else delete content[key]
  }
  return {
    kind: METADATA,
    created_at: Math.floor(Date.now() / 1000),
    content: JSON.stringify(content),
    tags: Array.isArray(base.tags) ? base.tags : [],
  }
}

// The base content arrives as a JSON string (the stored event's content); tolerate an already-parsed object
// or anything malformed by falling back to an empty object (a first profile has no base).
function parseContent(raw) {
  if (raw && typeof raw === "object") return { ...raw }
  try {
    const parsed = JSON.parse(raw || "{}")
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

// Sign + broadcast the profile. Returns the signed event, per-relay results, and how many relays accepted it.
export async function broadcastProfile(fields, base, signer, relays) {
  const signed = await signer.signEvent(buildProfileEvent(fields, base))
  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(signed)
    return { event: signed, results, reached: results.filter((r) => r.status === "ok").length }
  } finally {
    set.close()
  }
}
