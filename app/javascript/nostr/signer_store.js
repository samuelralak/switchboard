import { Nip07Signer, Nip46Signer, NsecSigner } from "nostr/signer"

// The tab-scoped, in-memory registry of the ONE active signer. It survives Turbo Drive soft navigation
// (the JS module runtime persists across <body> swaps) and is lost only on a hard reload, where it is
// re-hydrated from a small NON-SECRET descriptor in localStorage. The decrypted nsec and the live bunker
// connection NEVER persist; only the per-account NIP-49 ciphertext map (switchboard.nsec.v2) and the
// bunker reconnect tuple (switchboard.bunker) do. Keys never reach the server; only signed events leave.
const METHOD_KEY = "switchboard.signer.method" // "nip07" | "nsec" | "bunker"
const NSEC_KEY = "switchboard.nsec" // legacy single-slot NIP-49 ncryptsec (read-only back-compat)
const NSEC_MAP_KEY = "switchboard.nsec.v2" // JSON { [pubkeyHex]: ncryptsec } -- pubkey-scoped saved keys
const NSEC_LAST_KEY = "switchboard.nsec.last" // the most-recently-saved pubkey (the pre-sign-in default)
const BUNKER_KEY = "switchboard.bunker" // JSON { clientSk, pubkey, relays }
const UNLOCK_TIMEOUT_MS = 60_000

let activeSigner = null
let verifiedPubkey = null // the account pubkey activeSigner was confirmed to control (identity gate cache)
let pendingUnlock = null // the promise wiring for an in-flight nsec unlock prompt

export function getSigner() {
  return activeSigner
}

export function hasSigner() {
  return activeSigner !== null
}

// Record the live signer for the tab and remember the method so a hard reload can re-hydrate. Disposes
// a different signer it replaces (zeroes nsec bytes / closes the bunker) so sessions are not orphaned.
export function setSigner(signer, method) {
  if (activeSigner && activeSigner !== signer) {
    activeSigner.dispose?.()
    activeSigner.close?.()
  }
  activeSigner = signer
  verifiedPubkey = null
  writeLocal(METHOD_KEY, method)
  return signer
}

export function savedMethod() {
  return readLocal(METHOD_KEY)
}

export function setBunkerDescriptor(descriptor) {
  writeLocal(BUNKER_KEY, JSON.stringify(descriptor))
}

// --- pubkey-scoped saved-key map (with single-slot back-compat) ---

function readNsecMap() {
  try {
    const raw = readLocal(NSEC_MAP_KEY)
    return raw ? JSON.parse(raw) : {}
  } catch {
    return {}
  }
}

// The saved ciphertext for an account, preferring the scoped map and falling back to the legacy slot only
// while no scoped entry exists yet (so a fresh map never silently shadows a pre-migration single-slot key).
export function nsecFor(pubkey) {
  const map = readNsecMap()
  if (pubkey && map[pubkey]) return map[pubkey]
  return Object.keys(map).length === 0 ? readLocal(NSEC_KEY) : null
}

// Save a ciphertext under its account pubkey, remember it as the most recent, and retire the now-ambiguous
// legacy slot. Each account keeps its own slot, so a second account no longer clobbers the first. The
// legacy slot is removed ONLY once the scoped write actually lands, so a quota/private-mode failure can
// never delete the user's only on-disk key.
export function saveNsec(pubkey, ciphertext) {
  const map = readNsecMap()
  map[pubkey] = ciphertext
  const wrote = writeLocal(NSEC_MAP_KEY, JSON.stringify(map))
  writeLocal(NSEC_LAST_KEY, pubkey)
  if (wrote) removeLocal(NSEC_KEY)
}

export function forgetNsec(pubkey) {
  const map = readNsecMap()
  delete map[pubkey]
  writeLocal(NSEC_MAP_KEY, JSON.stringify(map))
  if (readLocal(NSEC_LAST_KEY) === pubkey) removeLocal(NSEC_LAST_KEY)
  removeLocal(NSEC_KEY)
}

// The saved key the pre-sign-in dialog should offer (it has no account context yet): the most recently
// saved account, else any scoped entry, else the legacy slot. Returns { pubkey, ciphertext } or null
// (pubkey is null for a legacy-slot key, which predates scoping).
export function savedNsecEntry() {
  const map = readNsecMap()
  const keys = Object.keys(map)
  if (keys.length) {
    const last = readLocal(NSEC_LAST_KEY)
    const pubkey = last && map[last] ? last : keys[keys.length - 1]
    return { pubkey, ciphertext: map[pubkey] }
  }
  const legacy = readLocal(NSEC_KEY)
  return legacy ? { pubkey: null, ciphertext: legacy } : null
}

// Forget the key the pre-sign-in dialog offered (and the legacy slot).
export function forgetSavedNsec() {
  const entry = savedNsecEntry()
  if (entry?.pubkey) return forgetNsec(entry.pubkey)
  removeLocal(NSEC_KEY)
}

// A legacy (unscoped) key that turns out to control a DIFFERENT account than the one signed in is scoped
// to its true owner here, so it is never again offered to unlock the wrong account (which would just fail
// the identity gate on every signing attempt). Non-destructive: the key survives under its real pubkey.
function migrateLegacyNsec(actualPubkey) {
  const legacy = readLocal(NSEC_KEY)
  if (legacy && Object.keys(readNsecMap()).length === 0) saveNsec(actualPubkey, legacy)
}

// A signed-in nsec user whose key is not in memory but who saved it can re-hydrate with a passphrase.
export function needsUnlock(pubkey) {
  return !activeSigner && savedMethod() === "nsec" && Boolean(nsecFor(pubkey))
}

// method is "nsec" but no saved ciphertext for this account: the in-memory signer was lost on reload and
// cannot be recovered without re-pasting the key, so the only path forward is to sign in again.
export function lostNsecSession(pubkey) {
  return !activeSigner && savedMethod() === "nsec" && !nsecFor(pubkey)
}

// Return the active signer, re-hydrating on a hard reload. NIP-07 re-acquires window.nostr; bunker
// reconnects from the saved descriptor (no onauth popup on silent restore: it would be popup-blocked
// outside a user gesture, so a revoked grant instead fails fast and the user is told to sign in again).
// nsec needs a passphrase: with `prompt` it opens the unlock dialog, otherwise returns null.
export async function ensureSigner({ prompt = false, onauth = null, pubkey = null } = {}) {
  if (activeSigner) return activeSigner

  switch (savedMethod()) {
    case "nip07":
      return Nip07Signer.available() ? setSigner(new Nip07Signer(), "nip07") : null
    case "bunker": {
      const descriptor = readBunker()
      return descriptor ? setSigner(await Nip46Signer.restore(descriptor, { onauth }), "bunker") : null
    }
    case "nsec":
      return prompt && needsUnlock(pubkey) ? requestUnlock() : null
    default:
      return null
  }
}

// Like ensureSigner, but also asserts the signer controls the signed-in account's `pubkey`. The first
// getPublicKey doubles as a reachability check, so a dead bunker surfaces a clear timeout rather than a
// misleading downstream error. Throws on mismatch (and disposes the wrong signer). Returns null when
// there is no usable credential. Every signing call site (uploads, listing publish, DMs) goes through it.
export async function ensureSignerFor(pubkey, opts = {}) {
  const signer = await ensureSigner({ ...opts, pubkey })
  if (!signer) return null
  // NIP-07's backing account can be switched in the extension out-of-band, so never trust the cache for
  // it -- always re-check. nsec/bunker keys are fixed once held, so the cache avoids a bunker round-trip.
  if (verifiedPubkey === pubkey && savedMethod() !== "nip07") return signer

  const actual = await signer.getPublicKey()
  if (actual !== pubkey) {
    if (savedMethod() === "nsec") migrateLegacyNsec(actual) // stop re-offering a legacy key to the wrong account
    lockSigner()
    throw new Error("This signer controls a different key than the account you're signed in as. Reconnect the matching signer, or sign in again.")
  }
  verifiedPubkey = pubkey
  return signer
}

// Decrypt the saved NIP-49 ciphertext and hold the resulting NsecSigner for the tab. The decrypted key
// lives in memory only. Distinguishes a library-load failure (offline / blocker) from a bad passphrase.
export async function unlockNsec(passphrase, pubkey) {
  const ciphertext = nsecFor(pubkey)
  if (!ciphertext) throw new Error("No saved key on this device.")
  let decrypt
  try {
    ({ decrypt } = await import("nostr-tools/nip49"))
  } catch {
    throw new Error("Couldn't load the signer library. Check your connection or content blocker.")
  }
  let secretKey
  try {
    secretKey = decrypt(ciphertext, passphrase)
  } catch {
    throw new Error("Incorrect passphrase.") // so the unlock dialog can surface every failure verbatim
  }
  return setSigner(new NsecSigner(secretKey), "nsec")
}

// --- nsec unlock prompt coordination (the signer-unlock dialog resolves these) ---

// Ask the UI to collect the passphrase. Returns a promise resolving to the unlocked signer, or null on
// cancel / if no dialog answers within the timeout (so a missing dialog never hangs the caller).
export function requestUnlock() {
  if (pendingUnlock) return pendingUnlock.promise
  let resolve
  const promise = new Promise((res) => { resolve = res })
  const timer = setTimeout(cancelUnlock, UNLOCK_TIMEOUT_MS)
  pendingUnlock = { promise, resolve, timer }
  document.dispatchEvent(new CustomEvent("signer:unlock-requested"))
  return promise
}

export function hasPendingUnlock() {
  return pendingUnlock !== null
}

export function resolveUnlock(signer) {
  if (!pendingUnlock) return
  clearTimeout(pendingUnlock.timer)
  pendingUnlock.resolve(signer)
  pendingUnlock = null
}

export function cancelUnlock() {
  if (!pendingUnlock) return
  clearTimeout(pendingUnlock.timer)
  pendingUnlock.resolve(null)
  pendingUnlock = null
}

// --- teardown ---

// Drop the in-memory signer (zero the nsec bytes / close the bunker) without forgetting descriptors.
export function lockSigner() {
  activeSigner?.dispose?.()
  activeSigner?.close?.()
  activeSigner = null
  verifiedPubkey = null
}

// Sign-out: lock, and forget the session descriptors. The saved NIP-49 ciphertext is the user's
// remember-this-device convenience and is removed only by the explicit "forget key" action.
export function clearSigner() {
  lockSigner()
  removeLocal(METHOD_KEY)
  removeLocal(BUNKER_KEY)
}

// --- private-browsing / quota-safe localStorage helpers (a write failure must never block sign-in) ---

// Returns whether the write landed; callers that retire a fallback (saveNsec) must not do so on failure.
function writeLocal(key, value) {
  if (!key) return false
  try { localStorage.setItem(key, value); return true } catch { return false } // private mode / quota
}

function readLocal(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function removeLocal(key) {
  try { localStorage.removeItem(key) } catch { /* ignore */ }
}

function readBunker() {
  try {
    const raw = readLocal(BUNKER_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

// Cross-tab sign-out: when another tab clears the signed-in method, evict the in-memory signer here too
// so a "disconnect" in one tab does not leave the key live in a sibling tab over a dead server session.
if (typeof window !== "undefined") {
  window.addEventListener("storage", (event) => {
    if (event.key === METHOD_KEY && event.newValue === null) lockSigner()
  })
}
