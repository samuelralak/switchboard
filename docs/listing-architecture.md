# Listing architecture: publishing and platform attestation

How a provider publishes a service to Switchboard, the conforming listing wire format, and how the
hosted platform asserts curation over a deliberately open, forkable protocol without breaking
non-custody. This is the catalog-side counterpart to `messaging-architecture.md`.

## The service-listing microstandard

A service is a standing **NIP-99 classified listing** (kind 30402) that carries a tight, documented set
of tags (brief 7.1) so a third-party client can render and invoke it from the convention alone. The
listing is the storefront; the work happens off-platform (a provider endpoint or a human).

| Field | Wire | Notes |
| --- | --- | --- |
| Service name | NIP-99 `title` | required to publish |
| Description | event `content` | Markdown |
| Capability | NIP-32 `["l", value, "<ns>.capability"]` | the queryable capability label (the intent router uses it). The "svc:" prefix some UIs show is display text only, not the tag |
| Price | NIP-99 `["price", n, "sat"]` | sat-only in v1 |
| Input schema | one `["input_schema", <JSON array>]` | a JSON array of fields, one tag (never one tag per field). Each field carries a machine name, a human label, a type, and required |
| Fulfillment mode | `["fulfillment", "automated"\|"manual"]` | determines the escrow mechanism, not a trust level |
| Endpoint (automated) | `["endpoint", url]` | the runtime forwards each paid request here |
| Delivery window (manual) | `["delivery_window", "24h"\|"3d"]` | sets the acceptance deadline clock (brief 10.1) |
| Image | NIP-99 `image` / NIP-92 `imeta` | the listing's hero image |
| Marker | `["t", "<namespace>-service"]` | the disambiguator that makes the catalog cleanly queryable |
| d / published_at / status | NIP-99 standard | the `d` tag is the addressable id; re-publishing under the same `d` supersedes |

There is deliberately **no payment-policy field**: escrow is a universal, platform-set guarantee on
every transaction (brief 10), never declared per listing.

### Environment-scoped marker

The marker tag is environment-scoped so development, staging, and test listings never pollute the
production catalog: production uses `switchboard-service`; non-production environments use a suffixed
form (for example `switchboard-service-development`). It lives in one place (`Catalog::Listing.marker`)
and is used by both the publisher and the catalog query. The base value is still a placeholder pending
the project name (brief 14.1 / 14.3), with a re-key plan for when it is finalized.

## Publishing is non-custodial

A provider publishes from the browser, signing with their own key. The server never holds a provider's
key and never creates the listing on their behalf:

1. The provider fills the studio form; the browser assembles a conforming kind-30402 plus a NIP-89
   handler announcement (kind 31990) that declares the provider's npub handles this service.
2. Both events are signed in the browser with the provider's signer (NIP-07 / NIP-46 / nsec), reusing
   the same signer stack as sign-in and messaging.
3. The events are broadcast to relays directly from the browser.
4. The existing server-side relay-ingest pipeline (`Catalog::Ingest` + `Events::Upsert` +
   `Catalog::Listing`) catalogs the listing with no new server-write code; the `d` tag handles
   supersede on edit.

Images are uploaded over a Nostr media path (NIP-96 with NIP-98 auth, or Blossom) authorized by the
**user's** signer, so the upload is non-custodial too; the resulting URL goes into the listing's image
tag. The file lives on a third-party host (a disclosed availability and privacy tradeoff).

## Platform attestation (anti-bypass for paid hosted listings)

Switchboard is open source, so anyone can run the client or a fork and publish a listing carrying the
`switchboard-service` marker. A public tag string cannot be gated at the protocol level, and we do not
try to. Instead the hosted platform is the **trust anchor** via a platform-signed attestation:

- When a listing is published through the hosted platform (and, when the business model turns it on, the
  listing fee is paid), the platform publishes a **NIP-32 label event** (kind 1985) signed by a
  **platform key**, referencing the listing's coordinate, with an environment-scoped label namespace.
- The hosted catalog surfaces (or "Listed on Switchboard" badges) only attested listings. A bypass or
  fork listing carries no valid platform signature, so it cannot fake the badge.
- **Forgery-proof:** the label is signed by the platform key, which forks and other actors do not have.
- **Non-custodial:** the platform signs its own label event; it never touches the provider's key (the
  same posture as R_op publishing its own kind-10050 / NIP-89 events). The §6.3 invariant holds.
- **Paid gate:** the platform issues the attestation only after the listing fee is paid, a fee paid
  outright to the platform npub (never custodied, like the open-request posting fee). This is the
  paid-hosted-listing line, a business-model evolution of brief 14.13 (catalog fees are otherwise
  deferred).
- **Separable:** the attestation is its own event and does not change the listing wire format, so the
  browser-direct publish does not depend on it. It is driven server-side, by relay ingest or a
  NIP-98-authenticated notify endpoint.

Self-hosters run their own attestation key and catalog policy; the mechanism is configuration, not
hardcoded to the hosted operator (the open-core split).

### Status

The environment-scoped marker and the non-custodial publish flow ship with the provider-studio
publishing epic. The attestation issuance and the catalog gating are a deferred backend follow-on, with
these still to settle: the catalog policy (exclude unattested vs show-and-badge), the platform key
(reuse R_op vs a dedicated attestation key), the exact label namespace, and the fee timing.
