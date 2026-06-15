// Report a freshly published kind-30402 (a service listing from the studio, or an open request from the
// request form) to the platform so it can attest it (the interim attestation trigger). Best-effort and
// fire-and-forget: the event is already live on relays, so a failed or declined report never affects the
// publish. Session-authenticated via CSRF, the same standard as the studio/requests flows (not NIP-98 /api).
export function reportForAttestation(event) {
  const token = document.querySelector("meta[name='csrf-token']")?.content

  return fetch("/attestations", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
    body: JSON.stringify({ event }),
  }).catch(() => { /* best-effort; the listing/request is already published to relays */ })
}
