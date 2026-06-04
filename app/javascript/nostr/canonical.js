import { getEventHash } from "nostr-tools/pure"

// The NIP-01 event id: sha256 of the canonical JSON [0, pubkey, created_at, kind, tags, content].
// nostr-tools' getEventHash serializes with JSON.stringify, which -- like Ruby's JSON.generate in
// Events::Actions::ComputeCanonicalId -- leaves &, <, > LITERAL (never HTML-escaped). So the browser
// and the Ruby spine compute the same id. Verified byte-for-byte against the shared nip59 vector; an
// HTML-escaping serializer here would silently fail every unwrap and every relay id check.
export function eventId(event) {
  return getEventHash(event)
}
