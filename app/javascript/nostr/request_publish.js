import { RelaySet } from "nostr/relay_set"

// Assembles, signs, and broadcasts an open request (a funded bounty, brief §10.2) non-custodially: a
// single NIP-99 kind-30402 event carrying the request marker. It is the demand-side inverse of a
// listing, so there is no NIP-89 handler announcement (a request states a need, it does not advertise
// a service handler). Signed with the CONSUMER's key (never R_op, §6.3) and broadcast to the catalog
// relays, where the server ingest routes it to the request board by its marker. The tag shape MUST
// match Requests::Draft / Requests::OpenRequest exactly -- that is the read contract.
//
// NOTE: this publishes the request EVENT only. The funded-bounty mechanics (the budget escrow deposit
// and the non-refundable posting fee, brief §10.2) land with escrow; until then a request is publish-only.
const CLASSIFIED = 30402 // NIP-99

// Build the kind-30402 template from the composer form `data` and the server `config`
// ({ marker, capabilityNamespace }). A caller may pass data.dTag to re-publish under the same
// coordinate (edit); otherwise a fresh stable id is minted.
export function buildRequestEvent(data, config) {
  assertPublishable(data)
  const now = Math.floor(Date.now() / 1000)
  // Monotonic created_at: bump past the prior version so an edit/re-publish reliably supersedes the
  // coordinate (NIP-01 tie-break drops an equal-or-lower created_at).
  const createdAt = Math.max(now, (Number(data.createdAt) || 0) + 1)
  const dTag = data.dTag || randomId()

  const request = { kind: CLASSIFIED, created_at: createdAt, content: data.description || "", tags: requestTags(data, dTag, config, now) }
  return { request, dTag, coordinatePrefix: `${CLASSIFIED}:` }
}

function requestTags(data, dTag, config, now) {
  const tags = [
    ["d", dTag],
    ["title", data.title || ""],
    ["published_at", data.publishedAt || String(now)], // carried on edit; the original post date
    ["status", data.status || "active"], // "active" = open/unclaimed; the lifecycle lands with escrow
    ["t", config.marker],
  ]
  // Capability shares the listing namespace so a request matches a provider's listing capability.
  if (data.capability) tags.push(["l", data.capability, config.capabilityNamespace])
  // The funded budget reuses NIP-99's price tag; a bounty is one fixed amount (no recurring frequency).
  if (data.budget) tags.push(["price", String(data.budget), "sat"])
  if (data.deliveryWindow) tags.push(["delivery_window", data.deliveryWindow])
  if (data.claimWindow) tags.push(["claim_window", data.claimWindow])
  // The escrow tier the poster opts into (Requests::OpenRequest#escrow_tier reads it back). Absent =>
  // tier-1; the composer only emits it when the platform arbiter is provisioned.
  if (data.escrowTier) tags.push(["escrow_tier", data.escrowTier])
  for (const image of data.images || []) {
    if (!image.url) continue
    tags.push(["image", image.url])
    const imeta = imetaTag(image)
    if (imeta) tags.push(imeta)
  }
  return tags
}

function imetaTag(image) {
  const parts = ["imeta", `url ${image.url}`]
  if (image.m) parts.push(`m ${image.m}`)
  if (image.x) parts.push(`x ${image.x}`)
  if (image.dim) parts.push(`dim ${image.dim}`)
  return parts.length > 2 ? parts : null
}

function randomId() {
  return Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) => b.toString(16).padStart(2, "0")).join("")
}

// Builder-level guard (defense in depth): a request can never be signed/broadcast without the fields the
// board read-contract + composer validation require. Mirrors request_form_controller#validate. Keep the
// isPositiveInt regex in sync there.
function assertPublishable(data) {
  const str = (value) => (value == null ? "" : String(value)).trim()
  const missing = []
  if (!str(data.title)) missing.push("title")
  if (!str(data.capability)) missing.push("capability")
  if (!/^\d+$/.test(str(data.budget)) || Number(str(data.budget)) <= 0) missing.push("budget")
  if (!str(data.deliveryWindow)) missing.push("delivery window")
  if (!str(data.claimWindow)) missing.push("claim window")
  if (missing.length) throw new Error(`Request is missing required fields: ${missing.join(", ")}.`)
}

function tagValue(event, name) {
  return (event.tags || []).find((t) => t[0] === name)?.[1]
}

// The newest event matching a filter on these relays, or null (EOSE / timeout). Used to flip status on
// the CURRENT version rather than a possibly-stale render-time snapshot (another tab may have edited it).
function fetchLatest(set, filter, ms = 4000) {
  return new Promise((resolve) => {
    let latest = null
    const sub = set.subscribeMany([filter], {
      onevent: (e) => { if (!latest || (Number(e.created_at) || 0) > (Number(latest.created_at) || 0)) latest = e },
      oneose: () => { sub.close(); resolve(latest) },
    })
    setTimeout(() => { sub.close(); resolve(latest) }, ms)
  })
}

// Withdraw / re-post: re-sign the request with its status tag flipped (everything else preserved, so it is
// reversible) and broadcast it. Re-fetches the latest version of the coordinate first so the flip usually
// applies to a concurrent edit's content, not a stale snapshot. Best-effort: if the relays serve nothing
// back (EOSE/timeout) it falls back to the render-time snapshot, which can still revert an edit that has
// not yet propagated to these relays. A fresh created_at supersedes the coordinate; the public board hides
// any non-"active". Unlike a listing there is no NIP-89 handler to keep in sync (a request advertises no
// service), so this is just the single re-signed event.
export async function setRequestStatus(event, status, signer, relays) {
  const set = new RelaySet(relays, { signer })
  try {
    const dTag = tagValue(event, "d") || ""
    const pubkey = await signer.getPublicKey()
    const latest = await fetchLatest(set, { kinds: [event.kind], authors: [pubkey], "#d": [dTag] })
    const base = latest && (Number(latest.created_at) || 0) >= (Number(event.created_at) || 0) ? latest : event

    const tags = (base.tags || []).filter((t) => t[0] !== "status").concat([["status", status]])
    const createdAt = Math.max(Math.floor(Date.now() / 1000), (Number(base.created_at) || 0) + 1)
    const signed = await signer.signEvent({ kind: base.kind, created_at: createdAt, content: base.content || "", tags })

    const results = await set.publishToMany(signed)
    return { event: signed, results, reached: results.filter((r) => r.status === "ok").length }
  } finally {
    set.close()
  }
}

// Sign + broadcast the request event. Returns the signed event, its addressable coordinate, and
// per-relay results.
export async function broadcastRequest(data, config, signer, relays) {
  const { request, dTag } = buildRequestEvent(data, config)
  const signed = await signer.signEvent(request)

  const set = new RelaySet(relays, { signer })
  try {
    const results = await set.publishToMany(signed)
    return {
      event: signed,
      coordinate: `${CLASSIFIED}:${signed.pubkey}:${dTag}`,
      results,
      reached: results.filter((r) => r.status === "ok").length,
    }
  } finally {
    set.close()
  }
}
