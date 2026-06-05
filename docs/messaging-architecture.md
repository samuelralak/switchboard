# Messaging architecture: non-custodial NIP-17

Switchboard's private messaging (orders and chat) is end-to-end encrypted between the two parties,
and the server is deliberately **not** able to read it. This document explains why the crypto runs
in the browser even though an identical implementation exists on the server, who can decrypt what,
and the contract that keeps the two implementations byte-compatible.

## The principle: non-custodial

A user's Nostr secret key (`nsec`) **never** reaches the server. It lives only in the browser, held
by the user's signer:

- a **NIP-07** browser extension (`window.nostr`),
- a **NIP-46** remote signer ("bunker"), or
- a pasted **nsec** (optionally saved NIP-49-encrypted in `localStorage`, never in a cookie).

The Rails runtime holds exactly one key of its own: **R_op**, a low-privilege operational identity
(`Operational::Signer`, from `R_OP_PRIVATE_KEY`). R_op is never a user key and never holds funds.

## Two key-holders, one protocol

NIP-17 private messages are wrapped per NIP-59:

```
gift wrap (kind 1059, signed by a fresh EPHEMERAL key)   <- addressed to the recipient (p-tag)
└─ seal  (kind 13, signed by the AUTHOR's real key)      <- encrypted to the recipient
   └─ rumor (kind 14 chat / 15 file, UNSIGNED)           <- the actual message
```

NIP-44 v2 encrypts each layer. The same protocol is implemented twice, for two different key-holders:

| | Implementation | Holds | Can decrypt |
| --- | --- | --- | --- |
| **Browser** | `app/javascript/nostr/*` | the user's key (via the signer) | messages addressed to the user |
| **Server** | `app/services/messages/*`, `lib/nip44.rb` | only R_op | only wraps addressed to R_op |

This is the crux: **NIP-17 decryption requires the recipient's private key.** A consumer→provider
message is sealed by the consumer and addressed to the provider, so:

- **Sending** it needs the consumer's key, only in the consumer's browser.
- **Reading** it needs the provider's key, only in the provider's browser.

The server is neither party and holds neither key, so it **cannot** encrypt or decrypt these
messages. The provider's inbox is decrypted in the provider's browser and is **never** server-rendered
from plaintext; only opaque kind-1059 wraps may ever be persisted server-side.

### Why not just do it on the server?

Routing user messages through the server (encrypting/decrypting with a server key) would make the
server a plaintext interception point, effectively custodial of message content. That model was
considered and **rejected** (2026-06-04, "minimize/e2e"). The browser is the only place this crypto
can legitimately run without breaking non-custody.

## The server's role

For private messaging, the server is **out of the loop**. The browser is its own Nostr client and
talks to relays directly (see "Relay transport" below); the server is **not** a relay, a proxy, or a
message store. Concretely, the server does **not**:

- read, decrypt, or render any user message or order content, it holds no user key;
- relay or forward messages between users, browser ↔ relay is direct;
- persist message **plaintext**, only opaque kind-1059 wraps are ever stored, as a cold-start cache
  (see "Cold-start inbox cache" below); the server never decrypts them.

What the server **does** do:

- **Serve the app**, HTML, the importmap JS, the sign-in session, the JSON API.
- **Ingest the public catalog**, a server-side relay client (the #31 R_op client) subscribes to
  kind-30402 service listings, which are public and unencrypted, and indexes them for search.
- **Act as R_op, and only R_op.** With its one operational key it authenticates to relays (NIP-42),
  publishes its *own* events (kind-10050 DM relay list, NIP-89 handler announcement), and decrypts
  **only** the opaque escrow-coordination signals gift-wrapped *to R_op itself* (lock / release /
  refund). It never decrypts a message between two users. (Escrow is a later epic; chat ships first.)

So there are **two separate Nostr clients** that share the wire format but never the keys: the
**server-side** one (`lib/nostr_client/*`, keyed by R_op, for catalog ingest and R_op's escrow role)
and the **browser** one (`app/javascript/nostr/*`, keyed by the user, for private messaging). A user
DM never passes through the server-side client, and R_op never touches a user DM.

## Cold-start inbox cache

Primary delivery is **always** the recipient's kind-10050 inbox relays (Send/Receive flows below);
the wraps live there. On top of that, Switchboard keeps an **opaque, Switchboard-controlled copy** of
each wrap (`InboxWrap` + `Messages::StoreWrap` + `InboxController`, `/inbox`) so a returning user can
rebuild its inbox on cold start (and across devices) without waiting on relay availability. It stores
**only** kind-1059 wraps and **never** decrypts, the server learns no more than any relay: the
recipient p-tag, an ephemeral sender pubkey, a randomized timestamp, and ciphertext.

The two halves have deliberately different trust models:

- **Deposit, `POST /inbox`, anonymous.** Like a relay accepting an `EVENT`: no cookie, no NIP-98, so
  the gift wrap's sender-hiding survives. The wrap is verified (sig + id + kind 1059 + a 64-hex
  recipient p-tag), stored as its canonical fields only, deduped by event id (before the quota, so a
  re-deposit is never wedged out), size-capped (256 KiB), per-recipient quota'd (`507` when full, not
  `422`), and rate-limited on a hashed IP, all **identity-free**. Retention is the earlier of 30 days
  and the wrap's own NIP-40 expiration, swept by a daily `prune_expired` reaper. A session- or
  NIP-98-authenticated deposit was rejected by design: it would resolve to the sender's real pubkey and
  bind it (plus IP/user-agent) to the recipient, rebuilding the exact sender→recipient graph NIP-17
  exists to destroy. Residual griefing: because the deposit is anonymous, a flood of valid junk wraps
  p-tagged at a victim can fill that victim's cache quota; only the cache degrades (new deposits get
  `507`), never delivery, the wrap still reaches the recipient via their kind-10050 relays. NIP-13
  proof-of-work is the anonymity-safe escalation if this is ever abused.
- **Fetch, `GET /inbox`, session-authenticated.** The signed-in cookie already proves the fetcher's
  pubkey (`Current.user`), so the server returns **only that recipient's** wraps, no per-request
  NIP-98 signing needed. A JSON consumer gets `401` when not signed in.

**Honest limits.** This HTTP store is reachable **only by Switchboard's own browser client**, no
third-party NIP-17 client (Damus, Amethyst, 0xchat) deposits over HTTP; they all publish to the
recipient's kind-10050 relays. So it is a Switchboard↔Switchboard convenience cache, not an
interoperable delivery path. The interoperable, durable, Switchboard-controlled answer is to run our
**own recipient-only AUTH-gated inbox relay** listed in users' kind-10050 (deferred: fortify
`relay_rb`); when that ships, this HTTP store is retired in its favour. One residual leak, named not
hidden: the row's wall-clock arrival time (the fetch cursor key) retains timing the randomized 1059
timestamp tries to hide, relay-equivalent, bounded by a 30-day retention reaper, and the deposit path
neither stores nor logs the source IP.

## Send flow (browser)

1. Build the unsigned **rumor** (kind 14).
2. **Seal** it: `signer.nip44Encrypt(recipient, rumorJSON)` then `signer.signEvent({kind: 13, ...})`
   with the user's key.
3. **Gift-wrap** it under a fresh ephemeral key (`nip44` + `finalizeEvent`), p-tagged to the recipient.
4. Wrap a second copy addressed to the sender's own pubkey (so the message appears in the sender's
   own thread, NIP-17 requires both).
5. Resolve each recipient's **kind-10050** DM relay list and publish the wraps there (and to the
   sender's own DM relays).

## Receive flow (browser)

1. Subscribe to `kinds:[1059] #p:<self>` on the user's own DM relays (user-signed **NIP-42 AUTH** for
   AUTH-gated relays, the user signs the kind-22242, not R_op).
2. **Unwrap** each wrap with the user's signer (`app/javascript/nostr/nip17.js`), enforcing every
   NIP-17/59 invariant (full NIP-01 verify of wrap + seal, empty seal tags, recomputed rumor id, no
   sig on the rumor, no NUL bytes, and `seal.pubkey === rumor.pubkey` anti-impersonation).
3. Render client-side. Decrypted content never returns to Rails.

## Interop contract (browser ↔ Ruby ↔ relays)

A browser-built wrap must be readable by the Ruby spine and by any relay, and vice versa. The two
implementations are kept byte-aligned and cross-tested against the same fixture
(`test/fixtures/files/nip59.vector.json`, in both directions):

- **Canonical event id**, `sha256(JSON [0, pubkey, created_at, kind, tags, content])` with `&`, `<`,
  `>` left **literal**. JS `JSON.stringify` matches Ruby's `JSON.generate` (`ComputeCanonicalId`); an
  HTML-escaping serializer would silently fail every id check.
- **NIP-44 v2 framing** byte-identical to `lib/nip44.rb` (HKDF split 32/12/32, ChaCha20 counter 0,
  MAC over `nonce || ciphertext`, base64 with padding).
- **Plaintext capped at 65535 bytes**, the Ruby spine uses a u16 length prefix, so larger payloads
  are unreadable server-side.
- **Layer shapes**: rumor unsigned with a real `created_at`; seal kind-13 with empty tags and a
  past-randomized `created_at`; wrap kind-1059 ephemeral-signed, `["p", recipient]`, independently
  past-randomized.

## Relay transport (browser)

The browser relay layer is built on nostr-tools' low-level `Relay` (not `SimplePool`, not NDK): it
exposes user-controllable NIP-42 AUTH (the relay hands a kind-22242 template to our signer and never
sees a key), per-event OK-correlation, and reconnection, with a thin hand-rolled manager for the
auth-required re-send (NIP-42), kind-10050 resolution, and multi-relay fan-out. The substrate pulls
only `@noble`, already used by the pinned `nostr-tools/pure`, so it needs no CSP change.

This is implemented as `app/javascript/nostr/relay_set.js` (the manager) and `dm_client.js` (the DM
engine), surfaced at `/dms` (`dm_client_controller`). It is **live-verified**: an env-gated test
(`test/system/dm_live_e2e_test.rb`, `SWITCHBOARD_LIVE_E2E=1`) delivers a real gift wrap end to end
through `wss://auth.nostr1.com`, real NIP-42 AUTH, publish with the auth-required re-publish, subscribe
delivery, and unwrap to plaintext. CI coverage runs against an in-page mock relay; the live test never
gates CI. (For the proof the messaging signer is the NIP-07 extension; an nsec/bunker session signer is
a later refinement, and order-scoped threads come with the services domain.)

## Trust boundaries, honestly

- The server can see **metadata** that reaches it (which pubkeys connect, when), but **not** message
  content, that is gift-wrapped end-to-end.
- Relays see only kind-1059 wraps (ephemeral sender pubkey, recipient p-tag, ciphertext).
- "Non-custodial" holds for keys, funds, and message content. It is not a claim that the system is
  fully trustless (relays and, later, escrow mints/nodes are residual trusted parties).
