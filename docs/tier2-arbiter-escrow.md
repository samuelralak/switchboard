# Tier-2 Arbiter Escrow (2-of-3 P2PK) — implementation plan

Status: **DESIGNED, not built. Awaiting ratification before any code.**

Tier-2 adds a non-custodial, arbiter-mediated escrow option for subjective / manual work, on top of the
shipped Tier-1 HTLC escrow. Tier-1 protects the consumer (they hold the preimage and release at will, refund
after locktime). Nothing in Tier-1 protects an honest *provider* against a dishonest consumer who refuses to
release. Tier-2 closes that gap with a platform-mediated 2-of-3.

This plan is grounded in source-verified facts (NUT-10/11/14 canonical spec, `@cashu/cashu-ts@4.5.1` source,
the live repo). Every load-bearing claim below was read first-hand from the cited source, not from memory.
The one fact that can only be settled empirically (real-mint acceptance of the 2-of-3 witness) is isolated
into Slice 2 as a merge gate.

---

## 1. Mechanism (source-verified)

A Tier-2 lock is a single NUT-11 **P2PK** proof (kind `P2PK`, **no hashlock** — that is what makes it
different from the Tier-1 HTLC):

```
["P2PK", {
  "nonce": "<random>",
  "data":  "<consumer_escrow_pubkey>",          // counts as a signer (see below)
  "tags": [
    ["pubkeys", "<provider_escrow_pubkey>", "<platform_arbiter_pubkey>"],
    ["n_sigs", "2"],
    ["locktime", "<unix_seconds>"],
    ["refund", "<consumer_escrow_pubkey>"],
    ["n_sigs_refund", "1"]
  ]
}]
```

**The `data` field counts toward the multisig threshold.** This was the one contradicted claim in research;
it is resolved with high confidence from three independent sources:

- NUT-11 (canonical): "the `Proof` is spendable only if a valid signature is given by at least ONE of the
  public keys contained in the `Secret.data` field **or** the `pubkeys` tag … Expressed as an n-of-m scheme,
  `n = n_sigs` and `m = 1 (data field) + count(pubkeys tag keys)`."
- `@cashu/cashu-ts@4.5.1` `getP2PKWitnessPubkeys`: `const keys = (data ? [data, ...pubkeys] : pubkeys)` —
  the `data` pubkey is prepended to the signer set.
- Confirmed by direct first-hand fetch of `nuts/main/11.md`.

So `{data=consumer, pubkeys=[provider, arbiter], n_sigs=2}` is a **true 2-of-3 over {consumer, provider,
arbiter}**. The earlier "set is only {provider, arbiter}" claim was a P2PK-vs-HTLC confusion (in HTLC, `data`
is the hash, not a pubkey) and is rejected.

### The four spend paths

| Path | Signers | Output goes to | Meaning |
|---|---|---|---|
| Happy | consumer + provider | provider | consumer approved, provider paid |
| Rule-for-provider | arbiter + provider | provider | dispute resolved for the provider |
| Rule-for-consumer | arbiter + consumer | consumer | dispute resolved for the consumer |
| Timeout refund | consumer alone (refund tag, after locktime) | consumer | no dispute resolved in time |

The arbiter (`pubkeys[1]`) is **1 of 3** and `n_sigs=2`, so the arbiter can never spend alone; the arbiter is
**not** in the `refund` tag, so it can never participate in the timeout refund. The arbiter is structurally a
**signer, never a custodian, never a payee**.

### Redemption reality (corrects the strawman)

`@cashu/cashu-ts@4.5.1` `wallet.receive(token, {privkey: [a, b]})` can sign a 2-of-3 **only when a single
holder owns both keys**. In Tier-2 the two signatures come from **two different holders** (a party's browser
+ the platform), so we cannot use `wallet.receive`. We must **partial-sign across holders**:

1. Holder A calls `signP2PKProof(proof, keyA)` → appends `sigA` to `witness.signatures`.
2. Holder B calls `signP2PKProof(proofWithSigA, keyB)` → appends `sigB`.
3. The final holder submits the now-2-signature inputs via the low-level `wallet.mint.swap(...)`.

This is the same hand-built-witness + `swapInputs` path the Tier-1 HTLC redeem already uses
(`cashu_escrow.js#redeemWithPreimage` / `swapInputs`), just with two signatures instead of a preimage. The
timeout refund (consumer alone, 1 sig) **can** use `wallet.receive(token, {privkey: consumerKey})` because it
is single-holder — identical to the existing Tier-1 `refund`.

`signP2PKProof(proof, privKey, message?)` signs a Schnorr signature over the proof's secret string (it does
**not** need `C`, the mint's unblinded signature). This is what lets the platform sign as arbiter without ever
holding a spendable proof (Section 4).

### Settlement direction (corrects the strawman)

NUT-07 checkstate returns `{Y, state, witness}` for each proof. It returns the **witness** (signatures/preimage
used) but **not the secret**. The secret carries a per-proof random nonce that Rails never stores (Rails stores
only `Y = hash_to_curve(secret)`, one-way). Therefore **Rails cannot verify which pubkeys signed a 2-of-3
spend** — it can read the witness *signature count* but cannot attribute the signatures.

Consequence: unlike Tier-1 (where the preimage in the witness is a self-proving "release" signal), Tier-2
**settlement direction (released vs refunded) cannot be derived from the mint**. Direction comes from Rails'
own authenticated records, with the mint used only to confirm the proofs are SPENT (finality / irreversibility):

- order is `disputed` and the **arbiter ruling** record says for-provider, proofs SPENT → **released**
- order is `disputed` and the arbiter ruling says for-consumer, proofs SPENT → **refunded**
- order is `funded` (no dispute), a **consumer release assertion** exists, proofs SPENT (≥2 sigs) → **released** (happy path)
- proofs SPENT with a **1-signature** witness → **refunded** (timeout refund path)

The witness signature count (1 vs ≥2) is the only thing read from the mint, and only to distinguish the
timeout-refund path; the *semantic* outcome is always anchored in a Rails-side record we authenticate
ourselves (the arbiter's own ruling, or the consumer's signed release assertion).

---

## 2. Trust model (disclose honestly)

A pure 2-of-3 means **arbiter + provider can release to the provider before locktime, without the consumer and
without proof of delivery.** This is **inherent and intended**, not a defect: it is precisely the power that
lets a mediator pay an honest provider when a dishonest consumer withholds. The research critique proposed an
"HTLC + 2-of-3 hybrid" that would require the consumer's preimage for any release — but that removes the
arbiter's ability to ever rule for the provider, which deletes the reason Tier-2 exists. So **pure 2-of-3 is
the correct design.**

The protection is therefore not cryptographic; it is:

1. **The arbiter is the platform itself**, reputation-bound, structurally never a payee, 1-of-3 so never
   sufficient alone. A platform has no incentive to burn its reputation colluding with a random provider over
   one small escrow.
2. **Tier-2 is opt-in**, for subjective/manual work, with a **conservative per-order cap** (lower than Tier-1).
3. **Honest disclosure** in the funding UI: "A platform arbiter can mediate disputes. You are trusting the
   platform not to collude with the provider. Use Tier-1 (self-release) for objective deliverables."

This is the standard 2-of-3 escrow trust model (cf. Bitcoin escrow, `cashu-escrow-kit`, `scrow`).

---

## 3. Must-fix hardenings (from the adversarial critique, all confirmed real)

1. **Server-inject the arbiter key (CRITICAL).** Because `data` counts as a signer, a consumer who supplies
   `arbiter = their own second key` would hold 2-of-3 and could drain the lock unilaterally (escrow becomes
   fake); the mirror holds for a provider-influenced key. For Tier-2 the `arbiter_pubkey` MUST equal the
   platform's published arbiter pubkey, validated server-side, and any client-supplied value rejected. For
   Tier-1 `arbiter_pubkey` MUST be absent.
2. **Fork `Orders::Settlement` on `order.tier` (CRITICAL).** Today `Settlement#released?` returns `false` when
   `order.lock.hashlock` is blank, so a Tier-2 lock (no hashlock) would *always* settle as REFUNDED, paying
   the wrong party. Tier-2 needs the records-anchored direction logic from Section 1.
3. **Min-locktime-lead.** The refund pathway is additive (spec: "[the multisig] conditions continue to apply
   … **In addition** the Proof can be spent" by the refund key), so post-locktime both the 2-of-3 and the
   1-of-1 refund are live (first-spend-wins). Enforce a generous minimum locktime lead so a dispute has time
   to resolve before the consumer's unilateral refund window opens.
4. **The `disputed` state + an arbiter ruling/signing interface.** Neither exists today; this is the bulk of
   the new build (Slices 1 and 4).

---

## 4. Non-custody argument

What the server stores for a Tier-2 lock is the same class of observable data as Tier-1: the lock terms
(`mint_url`, `lock_pubkey`, `arbiter_pubkey`, `refund_pubkey`, `n_sigs`, `n_sigs_refund`, `locktime`,
`amount`) and the proof `Y` values. **No secret, no nonce, no `C`, no spendable proof, no privkey** is ever
stored.

The platform arbiter key (a dedicated secp256k1 Cashu key, `ESCROW_TIER2_ARBITER_PRIVKEY`, held like
`R_OP_PRIVATE_KEY`, never logged) signs a proof **secret** at ruling time only:

- It signs the secret string, not the full proof, so the server need never see `C`.
- It is 1-of-3 with `n_sigs=2`, so even holding the arbiter key + transiently seeing a secret, the server
  **cannot spend** (it lacks a second key).
- It is never in the `refund` set and the swap output is always chosen by the *party*, never the server, so
  the arbiter is never a payee.

The arbiter is therefore a signer-not-custodian by construction, exactly like R_op publishing its own Nostr
events. Dedicated key (not R_op) because R_op signs Nostr events while the arbiter signs Cashu proof secrets —
different usage, cleaner separation.

---

## 5. Slice plan (de-risk first, money code last)

Each slice is independently shippable. Tier-1 is left **100% untouched** by construction (every fork keys on
`order.tier`, which defaults to `tier1_htlc`).

### Slice 1 — `disputed` state foundation (no behavior). Money-risk: none.

Add the `disputed` state so later slices have somewhere to land. Tier-1 orders never enter it.

- **Migration** `add_disputed_order_state`:
  - Drop + re-add `orders_current_state` check to include `disputed`.
  - Drop + re-add `order_transitions_from_state` and `order_transitions_to_state` checks to include `disputed`.
  - Drop + recreate `index_orders_active_order_per_consumer` and `index_orders_active_claim_per_request` with
    `disputed` added to the `current_state IN (...)` predicate (a disputed order is still an open order and
    must block a re-order). Partial-index predicates cannot be altered in place; drop + create.
- `app/models/orders/states.rb`: add `DISPUTED = "disputed"`; add to `ALL`; add to `ACTIVE` (so the `active`
  scope + the re-order guard agree with the index); add `SETTLEABLE = [FUNDED, DISPUTED].freeze` (the set the
  reconcile/settlement scan); extend `TRANSITIONS`: `FUNDED => [RELEASED, REFUNDED, DISPUTED]`,
  `DISPUTED => [RELEASED, REFUNDED]`.
- `app/models/orders/state_machine.rb`: the machine derives states + transitions from `States` automatically;
  add settlement-effect `after_transition` blocks for `from: DISPUTED, to: RELEASED` and
  `from: DISPUTED, to: REFUNDED` (mirroring the existing `from: FUNDED` blocks) so `order_effects` is still
  written exactly once on any terminal settlement.
- **Tests:** state-machine transition tests (funded→disputed→released/refunded legal; disputed terminal
  guards); a migration/schema test that the new state is accepted and a Tier-1 order never transitions to it.

### Slice 2 — live-mint 2-of-3 spike (MERGE GATE). Money-risk: none (test-only, FakeWallet).

Prove the mechanism against a real mint before any Rails settlement logic. Mirrors
`test/system/cashu_escrow_test.rb` + the `cashu_test_support.js` scenario pattern (local docker nutshell
FakeWallet, NUT-7/10/11/14, fees off). **No code from Slices 3-4 merges until this is green.**

- `app/javascript/nostr/cashu_escrow.js`: add `lockP2PK2of3({ wallet, amount, proofs, consumerPubkey,
  providerPubkey, arbiterPubkey, consumerRefundPubkey, locktime })` — a sibling of `lockHtlc` that builds
  `new P2PKBuilder().addLockPubkey([consumerPubkey, providerPubkey, arbiterPubkey]).requireLockSignatures(2)
  .addRefundPubkey(consumerRefundPubkey).lockUntil(locktime)` with **no `addHashlock`**. (Spike confirms the
  builder places the first `addLockPubkey` entry in `data` and the rest in `pubkeys`; if not, set `data`
  explicitly.) Add `coSignProof(proof, privkey)` (append one signature) and `redeem2of3(wallet, proofsWith2Sigs)`
  (submit via the existing `swapInputs`).
- `app/javascript/nostr/cashu_test_support.js`: a `tier2Escrow` scenario exercising all paths.
- **Spike assertions** (the merge gate) against the FakeWallet mint:
  - (a) happy: consumer-sig + provider-sig → swap SPENT, output redeemable by provider;
  - (b) rule-for-provider: arbiter-sig + provider-sig → SPENT;
  - (c) rule-for-consumer: arbiter-sig + consumer-sig → SPENT;
  - (d) timeout: after locktime, `wallet.receive(token, {privkey: consumerKey})` (1-of-1 refund) → SPENT;
  - (e) NEGATIVE: a single main-path signature (1-of-3) is REJECTED pre-`n_sigs`;
  - (f) NEGATIVE: a refund attempt **before** locktime is REJECTED;
  - (g) checkstate on each SPENT proof returns a witness whose `signatures.length` matches the path (1 for
    refund, ≥2 for the main paths) — this is the signal Slice 3 settlement relies on.
- **Resolves the only remaining empirical unknown:** that a real mint accepts/verifies the 2-of-3 witness and
  that the partial-sign-across-holders construction round-trips.

### Slice 3 — funding + settlement fork. Money-risk: high (gated by Slice 2 green + a funds-safety review).

Make Tier-2 orders fundable and settleable, server-side.

- **Migration** `relax_order_locks_hashlock_for_p2pk`: make `order_locks.hashlock` nullable; replace the
  `order_locks_hashlock_hex` check with `hashlock IS NULL OR hashlock ~ '^[0-9a-f]{64}$'`.
- **Platform arbiter key:** new `Escrow::ArbiterSigner` (holds `ESCROW_TIER2_ARBITER_PRIVKEY`, exposes the
  66-hex `pubkey`, `reader: :private`, never logged; `.configured?` gates Tier-2 availability), mirroring
  `Operational::Signer`. Add `ESCROW_TIER2_ARBITER_PRIVKEY` to `.env.example` + `config/initializers/escrow.rb`
  (and the public pubkey exposed to the browser via a data attribute on the funding UI).
- `app/contracts/orders/funding_contract.rb`: make it tier-aware.
  - Tier-1: `hashlock` required (current rules), `arbiter_pubkey` must be **absent**.
  - Tier-2: `hashlock` must be **absent**; `arbiter_pubkey` required and **must equal**
    `Escrow::ArbiterSigner.pubkey` (reject any other value); `required_signatures == 2`;
    `required_refund_signatures == 1`; `lock_pubkey`/`refund_pubkey` present (the consumer's escrow point in
    `data`/`refund`, the provider's in `pubkeys` — naming reconciled in the funding payload).
- `app/services/orders/funding.rb`: for Tier-2, omit `hashlock` from `lock_terms`, set `n_sigs=2`, Tier-1 path
  unchanged. **VALIDATE the reported arbiter (== the platform key), do NOT inject it** (this supersedes an
  earlier "inject" note). Rails cannot read the on-mint secret, so the lock the browser actually built is
  authoritative; overwriting the reported `arbiter_pubkey` with the platform key would only *hide* a mismatch
  — an honestly-reported wrong arbiter must be **rejected** (so the consumer re-locks correctly), not silently
  rewritten. Defense-in-depth is two server-side layers: `FundingContract` + the `OrderLock` model invariant.
  The remaining residual (a consumer who *lies*, locking to a non-platform arbiter but reporting the platform
  key) is bounded — they only risk their own refundable funds, and the **provider must independently verify
  the real on-mint 2-of-3 carries the platform arbiter before working** (Slice 4), which is the true backstop.
- `app/services/orders/settlement.rb`: fork on `order.tier`.
  - Tier-1: existing preimage-match logic, unchanged.
  - Tier-2: direction from Section 1 — a 1-signature witness ⇒ REFUNDED; otherwise consult the order's
    records (an `OrderDispute` ruling ⇒ per ruling; else a consumer release assertion ⇒ RELEASED). Guard
    widened from `current_state == FUNDED` to `States::SETTLEABLE.include?(current_state)`.
- `app/services/orders/reconcile.rb` + `app/jobs/escrow/reconcile_sweep_job.rb`: scan `States::SETTLEABLE`
  (`[funded, disputed]`) instead of `funded` only, so a disputed order whose proofs the arbiter+party spent is
  detected and settled.
- `app/models/orders/policy.rb` + `config/initializers/escrow.rb`: add `tier2_max_order_sats` (a lower cap)
  and `tier2_min_locktime_seconds` (the dispute-window lead); enforce in `FundingContract`/`Place`.
- `app/services/orders/place.rb` + `app/services/orders/create.rb`: already carry `tier`; ensure Tier-2 is
  selectable only where offered (Section 6 UI) and the per-tier cap is applied.
- **Browser:** `app/javascript/nostr/order_funding.js` gains a Tier-2 branch using `lockP2PK2of3`; the
  funding report carries `arbiter_pubkey`, `n_sigs`, no hashlock.
- **Tests:** funding contract (tier-1 rejects arbiter; tier-2 rejects non-platform arbiter, rejects hashlock);
  funding injects the platform arbiter; settlement tier-2 direction matrix (1-sig→refund, ruling→per-ruling,
  release-assertion→release); reconcile scans disputed; a cross-language `fundReport` Tier-2 scenario against
  the real mint (extends the Slice-2 spike into the Rails spine).

### Slice 4 — dispute lifecycle + arbiter ruling. Money-risk: high (funds-safety review).

The interface that makes the arbiter usable.

- **Migration** `create_order_disputes`: `order_disputes` (uuid pk, `order_id` uuid FK **UNIQUE** = one
  dispute per order, `opened_by_pubkey` 64-hex, `reason` text, `evidence_url` nullable, `status` in
  `[open, ruled_for_provider, ruled_for_consumer]`, `ruled_at` nullable, timestamps; a check on `status`).
- `app/services/orders/open_dispute.rb`: either party (consumer or provider on a `funded` Tier-2 order) opens a
  dispute → creates the `OrderDispute` and transitions `funded → disputed` (atomic, `with_lock`, idempotent).
- `app/services/orders/rule_dispute.rb`: the platform operator rules. Records `status`/`ruled_at`, then
  produces the **arbiter's detached signature** over the winning party's proof secrets via
  `Escrow::ArbiterSigner` (the party submits the secrets over an authenticated channel; the server signs and
  returns the signatures; the party adds their own signature and swaps to their chosen output). The
  `disputed → released|refunded` transition lands when the reconcile sweep confirms the proofs SPENT (the
  ruling record gives the direction).
- **Controller:** `OrdersController#dispute` (POST `orders/:id/dispute`, either party) and a platform-scoped
  ruling action (admin-gated; `OrdersController#rule` or a dedicated `Admin::DisputesController`). New routes.
  Reuse the `require_login` + `rate_limit` pattern.
- **Arbiter signing channel (open sub-decision, Section 7):** the simplest MVP is an authenticated endpoint
  (the party POSTs the proof secrets, the server returns arbiter signatures); a NIP-17 channel is the
  alternative. Either way the server signs the secret only, never persists it, never sees `C`.
- **UI:** a "Dispute" affordance on a funded Tier-2 order (`Orders::Actions`), a dispute panel in the order
  detail (status + evidence), and a minimal platform ruling surface (review evidence → rule for provider /
  consumer → the chosen party is handed the arbiter signature to complete the spend).
- **Browser:** `app/javascript/nostr/order_settlement.js` gains `verifyTier2Lock` (parse the P2PK 2-of-3
  secret), the happy-path consumer→provider co-sign flow, the dispute co-sign-with-arbiter flow, and the
  1-of-1 timeout refund (reusing `refund`).
- **Tests:** open-dispute service (only a party, only on funded tier-2, idempotent); rule-dispute (records +
  arbiter signs the secret; non-custody assertion that nothing spendable is stored); a cross-language dispute
  scenario (lock → open dispute → arbiter rules for provider → provider completes the 2-of-3 spend → reconcile
  → RELEASED) against the real mint; the mirror rule-for-consumer → REFUNDED; the timeout-refund path.

### Review gates

Adversarial funds-safety review (the find → dual-skeptic-verify pattern used for prior escrow slices) before
merging Slice 3 and again before Slice 4. Focus: the arbiter-injection gate, the settlement-direction logic,
the locktime-lead race, and the non-custody of the arbiter signing channel.

---

## 6. Where Tier-2 is offered (UI)

Tier-2 is opt-in at order placement. The provider's listing (or the open request) indicates Tier-2 eligibility
for subjective work; the consumer's order / claim form offers a Tier-1 (self-release) vs Tier-2 (mediated)
choice with the honest disclosure from Section 2. `Orders::Place` already carries `tier`; the catalog "Order"
button / claim form set it. Default stays Tier-1.

---

## 7. Open decisions

**Ratified (this session):**

- **Arbiter identity = platform-only (R_op-class dedicated key)** for the MVP. Server-injected, never
  user-supplied.

**Still open (smaller, can be decided during the build):**

- **Arbiter signing channel:** authenticated HTTP endpoint (simplest) vs NIP-17 (more aligned, heavier). MVP
  leans endpoint; revisit if a Nostr-native arbiter console is wanted.
- **Per-order Tier-2 cap + min-locktime-lead values** (config; conservative defaults: cap below Tier-1, lead
  generous enough for a dispute to resolve).
- **Dispute window:** until what point can a party open a dispute (any time while funded, or until some
  pre-locktime cutoff)?

---

## 8. Post-MVP / future improvements (documented now, not built)

- **Consumer-nominated arbiters (the rejected Option 2).** Let the consumer choose an arbiter from a vetted
  allowlist of third-party arbiters at funding, instead of always the platform. More decentralized; removes
  the platform as the single mediator. Requires: an arbiter registry + discovery (likely a Nostr
  announcement / NIP-89-style handler), per-arbiter reputation, a generalized signing channel so any arbiter
  (not just the platform) can receive and sign disputes, and an arbiter-selection step in the funding UI. The
  Tier-2 wire format already supports it (the `arbiter_pubkey` is just a different key); the work is the
  registry, reputation, and multi-arbiter routing. **The server-injection gate (Section 3.1) must then become
  "arbiter_pubkey ∈ the vetted allowlist" rather than "== the platform key."**
- **Arbiter bonds / slashing.** `scrow` and others bond the arbiter so misbehavior is punishable. Out of MVP
  scope (the platform's reputation is the MVP bond), but a natural addition once third-party arbiters exist.
- **How the Slice-2 spike feeds back.** The live-mint spike (Slice 2) is the source of truth for two things
  the MVP design assumes and the post-MVP work inherits: (1) whether `P2PKBuilder` places the first
  `addLockPubkey` entry in `data` (if not, every lock must set `data` explicitly — a one-line change that
  propagates to any future multi-arbiter builder); (2) the exact witness `signatures` shape and ordering the
  mint accepts (the settlement-direction signal). If the spike surfaces a mint-specific quirk (e.g. signature
  ordering, or a `SIG_ALL` requirement instead of the assumed `SIG_INPUTS`), that constraint is recorded here
  and applied uniformly to both the platform-arbiter MVP and the later consumer-nominated path before either
  ships settlement code.

---

## 9. Source citations

- NUT-10/11/14 canonical: `https://raw.githubusercontent.com/cashubtc/nuts/main/{10,11,14}.md`
  (read first-hand; `m = 1 (data field) + count(pubkeys)`; additive refund pathway; SIG_INPUTS default).
- `@cashu/cashu-ts@4.5.1` (tag `v4.5.1`): `src/crypto/NUT11.ts` (`getP2PKWitnessPubkeys` =
  `[data, ...pubkeys]`, `signP2PKProof`), `src/wallet/P2PKBuilder.ts`, `src/wallet/Wallet.ts`
  (`completeSwap`/`mint.swap`), `src/wallet/types/config.ts` (`ReceiveConfig.privkey`). `@cashu/crypto` is
  **not** a 4.5.1 dependency; the P2PK crypto is internal (uses `@noble/curves` schnorr).
- Prior art: `f321x/cashu-escrow-kit` (same 2-of-3 shape; coordinator signing left as a `// todo`),
  `storopoli/scrow` (Taproot 2-of-3 + asymmetric dispute scripts), Mostro (Lightning hold-invoice arbiter).
- Live repo: `app/services/orders/{settlement,funding,reconcile,place,create,policy}.rb`,
  `app/models/orders/{states,state_machine,tiers}.rb`, `app/models/order.rb`,
  `app/contracts/orders/funding_contract.rb`, `app/services/cashu/actions/parse_witness.rb`,
  `app/javascript/nostr/{cashu_escrow,order_settlement,order_funding}.js`,
  `app/controllers/orders_controller.rb`, `db/schema.rb`.
