import { RelaySet } from "nostr/relay_set"

// Assembles, signs, and broadcasts a provider's service listing, non-custodially:
//   - a NIP-99 kind-30402 classified listing (the catalog entry), and
//   - a NIP-89 kind-31990 handler announcement (discovery: this npub handles the capability).
// Both are signed with the PROVIDER's key (never R_op, brief §6.3) and broadcast to the catalog's
// relays, where the server ingest pipeline catalogs the listing. The kind-30402 tag shape MUST match
// Catalog::Draft / Catalog::Listing exactly -- that is the read contract.
const CLASSIFIED = 30402 // NIP-99
const HANDLER_INFO = 31990 // NIP-89

// Build the kind-30402 + kind-31990 templates from the studio form `data` and the server `config`
// ({ marker, capabilityNamespace, origin }). A caller may pass data.dTag to re-publish under the same
// coordinate (edit); otherwise a fresh stable id is minted.
export function buildEvents(data, config) {
  assertPublishable(data)
  const now = Math.floor(Date.now() / 1000)
  // Monotonic created_at: bump past the prior version so an edit/re-publish reliably supersedes the
  // coordinate (NIP-01 tie-break drops an equal-or-lower created_at).
  const createdAt = Math.max(now, (Number(data.createdAt) || 0) + 1)
  const dTag = data.dTag || randomId()

  const listing = { kind: CLASSIFIED, created_at: createdAt, content: data.description || "", tags: listingTags(data, dTag, config, now) }
  const handler = { kind: HANDLER_INFO, created_at: createdAt, content: "", tags: handlerTags(data, dTag, config) }
  return { listing, handler, dTag, coordinatePrefix: `${CLASSIFIED}:` }
}

function listingTags(data, dTag, config, now) {
  const tags = [
    ["d", dTag],
    ["title", data.title || ""],
    ["published_at", data.publishedAt || String(now)], // carried on edit; the original publish date
    ["status", data.status || "active"], // carried on edit (preserve visibility); "active" for a new listing
    ["t", config.marker],
  ]
  if (data.capability) tags.push(["l", data.capability, config.capabilityNamespace])
  if (data.price) {
    // NIP-99 price tag; the optional 4th element is the recurring frequency ("hour" = per-hour rate,
    // omitted = a one-time per-request price).
    const price = ["price", String(data.price), "sat"]
    if (data.priceFrequency) price.push(data.priceFrequency)
    tags.push(price)
  }
  if (data.fulfillment) tags.push(["fulfillment", data.fulfillment])
  if (data.fulfillment === "automated" && data.endpoint) tags.push(["endpoint", data.endpoint])
  if (data.fulfillment === "manual" && data.deliveryWindow) tags.push(["delivery_window", data.deliveryWindow])
  if (data.schema && data.schema.length) tags.push(["input_schema", JSON.stringify(data.schema)])
  for (const image of data.images || []) {
    if (!image.url) continue
    tags.push(["image", image.url])
    const imeta = imetaTag(image)
    if (imeta) tags.push(imeta)
  }
  return tags
}

// NIP-89: declares this npub handles kind-30402 service listings (discoverable by capability + marker).
// content stays empty so clients fall back to the provider's kind-0 profile. Shares the listing's d-tag.
function handlerTags(data, dTag, config) {
  const tags = [["d", dTag], ["k", String(CLASSIFIED)], ["t", config.marker]]
  if (data.capability) tags.push(["l", data.capability, config.capabilityNamespace])
  // NIP-89 generic handler: a `web` tag with no second value is the fallback for any NIP-19 entity. We
  // declare the app origin only because Switchboard has no per-listing route yet (listings open in an
  // in-page dialog). Once an `/a/:naddr` permalink exists, add an entity-typed template ALONGSIDE this:
  //   ["web", `${config.origin}${config.pathTemplate}`, "naddr"]  // <bech32> stays literal; the consumer
  // substitutes its own naddr. The type is "naddr" (not "nevent"): a kind-30402 is addressable by
  // kind:pubkey:d, so it stays stable across re-publish/supersede, whereas an event id would dangle.
  if (config.origin) tags.push(["web", config.origin])
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

// Builder-level guard (defense in depth): a listing can never be signed/broadcast without the fields the
// catalog read-contract + studio validation require. Mirrors studio_controller#validate (title, capability,
// price = whole number > 0). setListingStatus is exempt by design (it re-signs an already-valid stored
// event, not form data, so it never reaches buildEvents). Keep this regex in sync with isPositiveInt there.
function assertPublishable(data) {
  const str = (value) => (value == null ? "" : String(value)).trim()
  const missing = []
  if (!str(data.title)) missing.push("title")
  if (!str(data.capability)) missing.push("capability")
  if (!/^\d+$/.test(str(data.price)) || Number(str(data.price)) <= 0) missing.push("price")
  if (missing.length) throw new Error(`Listing is missing required fields: ${missing.join(", ")}.`)
}

function tagValue(event, name) {
  return (event.tags || []).find((t) => t[0] === name)?.[1]
}

// Keep the NIP-89 handler announcement in sync with the listing's visibility (best-effort discovery
// metadata, never fatal): a re-sign when active, a NIP-09 (kind-5) deletion of the handler coordinate
// when unpublished. Returns the signed event or null (declined / not applicable).
async function handlerSync(event, status, config, signer, createdAt) {
  try {
    const dTag = tagValue(event, "d") || ""
    if (status === "active") {
      const tags = handlerTags({ capability: tagValue(event, "l") }, dTag, config)
      return await signer.signEvent({ kind: HANDLER_INFO, created_at: createdAt, content: "", tags })
    }
    const pubkey = await signer.getPublicKey()
    const tags = [["a", `${HANDLER_INFO}:${pubkey}:${dTag}`], ["k", String(HANDLER_INFO)]]
    return await signer.signEvent({ kind: 5, created_at: createdAt, content: "Withdraw service handler", tags })
  } catch {
    return null
  }
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

// Unpublish / re-publish: re-sign the listing with its status tag flipped (everything else preserved,
// so it is reversible) and broadcast it, keeping the NIP-89 handler in sync. Re-fetches the latest
// version of the coordinate first so the flip usually applies to a concurrent edit's content, not a
// stale snapshot. Best-effort: if the relays serve nothing back (EOSE/timeout), it falls back to the
// render-time snapshot, which can still revert an edit that has not yet propagated to these relays. A
// fresh created_at supersedes the coordinate; the public catalog hides any non-"active".
export async function setListingStatus(event, status, config, signer, relays) {
  const set = new RelaySet(relays, { signer })
  try {
    const dTag = tagValue(event, "d") || ""
    const pubkey = await signer.getPublicKey()
    const latest = await fetchLatest(set, { kinds: [event.kind], authors: [pubkey], "#d": [dTag] })
    const base = latest && (Number(latest.created_at) || 0) >= (Number(event.created_at) || 0) ? latest : event

    const tags = (base.tags || []).filter((t) => t[0] !== "status").concat([["status", status]])
    const createdAt = Math.max(Math.floor(Date.now() / 1000), (Number(base.created_at) || 0) + 1)
    const signed = await signer.signEvent({ kind: base.kind, created_at: createdAt, content: base.content || "", tags })
    const handler = await handlerSync(base, status, config, signer, createdAt)

    const results = await set.publishToMany(signed)
    if (handler) await set.publishToMany(handler).catch(() => {}) // best-effort: the listing flip is what matters
    return { event: signed, results, reached: results.filter((r) => r.status === "ok").length }
  } finally {
    set.close()
  }
}

// Sign + broadcast. The listing is the critical event; the handler announcement is best-effort discovery
// metadata, so a failure there (or a declined second signature) does not fail the publish. Returns the
// signed listing, its addressable coordinate, and per-relay results for each event.
export async function broadcastListing(data, config, signer, relays) {
  const { listing, handler, dTag } = buildEvents(data, config)
  const signedListing = await signer.signEvent(listing)

  const set = new RelaySet(relays, { signer })
  try {
    const listingResults = await set.publishToMany(signedListing)

    let handlerResults = []
    try {
      const signedHandler = await signer.signEvent(handler)
      handlerResults = await set.publishToMany(signedHandler)
    } catch (error) {
      handlerResults = [{ url: "(handler)", status: "error", reason: error.message }]
    }

    return {
      event: signedListing,
      coordinate: `${CLASSIFIED}:${signedListing.pubkey}:${dTag}`,
      listingResults,
      handlerResults,
      reached: listingResults.filter((r) => r.status === "ok").length,
    }
  } finally {
    set.close()
  }
}
