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

- **Sending** it needs the consumer's key — only in the consumer's browser.
- **Reading** it needs the provider's key — only in the provider's browser.

The server is neither party and holds neither key, so it **cannot** encrypt or decrypt these
messages. The provider's inbox is decrypted in the provider's browser and is **never** server-rendered
from plaintext; only opaque kind-1059 wraps may ever be persisted server-side.

### Why not just do it on the server?

Routing user messages through the server (encrypting/decrypting with a server key) would make the
server a plaintext interception point — effectively custodial of message content. That model was
considered and **rejected** (2026-06-04, "minimize/e2e"). The browser is the only place this crypto
can legitimately run without breaking non-custody.

## R_op's narrow role

R_op runs the *same* gift-wrap protocol, but only for itself: it decrypts **only** the opaque
escrow-coordination signals addressed to R_op (lock / release / refund), never order content, chat,
or identities. That is the entire reason the Ruby spine (`Messages::Seal/GiftWrap/Unwrap`,
`Operational::Publish`) exists server-side. (Escrow signals are a later epic; the chat path is built
first.)

## Send flow (browser)

1. Build the unsigned **rumor** (kind 14).
2. **Seal** it: `signer.nip44Encrypt(recipient, rumorJSON)` then `signer.signEvent({kind: 13, ...})`
   with the user's key.
3. **Gift-wrap** it under a fresh ephemeral key (`nip44` + `finalizeEvent`), p-tagged to the recipient.
4. Wrap a second copy addressed to the sender's own pubkey (so the message appears in the sender's
   own thread — NIP-17 requires both).
5. Resolve each recipient's **kind-10050** DM relay list and publish the wraps there (and to the
   sender's own DM relays).

## Receive flow (browser)

1. Subscribe to `kinds:[1059] #p:<self>` on the user's own DM relays (user-signed **NIP-42 AUTH** for
   AUTH-gated relays — the user signs the kind-22242, not R_op).
2. **Unwrap** each wrap with the user's signer (`app/javascript/nostr/nip17.js`), enforcing every
   NIP-17/59 invariant (full NIP-01 verify of wrap + seal, empty seal tags, recomputed rumor id, no
   sig on the rumor, no NUL bytes, and `seal.pubkey === rumor.pubkey` anti-impersonation).
3. Render client-side. Decrypted content never returns to Rails.

## Interop contract (browser ↔ Ruby ↔ relays)

A browser-built wrap must be readable by the Ruby spine and by any relay, and vice versa. The two
implementations are kept byte-aligned and cross-tested against the same fixture
(`test/fixtures/files/nip59.vector.json`, in both directions):

- **Canonical event id** — `sha256(JSON [0, pubkey, created_at, kind, tags, content])` with `&`, `<`,
  `>` left **literal**. JS `JSON.stringify` matches Ruby's `JSON.generate` (`ComputeCanonicalId`); an
  HTML-escaping serializer would silently fail every id check.
- **NIP-44 v2 framing** byte-identical to `lib/nip44.rb` (HKDF split 32/12/32, ChaCha20 counter 0,
  MAC over `nonce || ciphertext`, base64 with padding).
- **Plaintext capped at 65535 bytes** — the Ruby spine uses a u16 length prefix, so larger payloads
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

## Trust boundaries, honestly

- The server can see **metadata** that reaches it (which pubkeys connect, when), but **not** message
  content — that is gift-wrapped end-to-end.
- Relays see only kind-1059 wraps (ephemeral sender pubkey, recipient p-tag, ciphertext).
- "Non-custodial" holds for keys, funds, and message content. It is not a claim that the system is
  fully trustless (relays and, later, escrow mints/nodes are residual trusted parties).
