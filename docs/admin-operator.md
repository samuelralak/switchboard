# Admin (operator) access + testing

The admin surface has two pages, both gated by the same `OPERATOR_PUBKEYS` allowlist
(`config/initializers/operators.rb` → `Operator`): the **Tier-2 dispute ruling queue** at `/admin/disputes`
and the **takedown queue** at `/admin/flags`. There is no admin password or role: an operator signs in with
their normal Nostr key. A non-operator who visits either is quietly redirected home.

## Takedown: hide a pubkey's public content

`/admin/flags` flags or unflags a pubkey. A flagged author's service listings, open requests, and profile page
(`/u/:npub`) stop being served (`Event.not_from_flagged` on the catalog/board scopes; `Profiles::Resolve` 404s a
flagged identity). Paste an `npub…` or a 64-hex pubkey and Flag; Unflag reverses it. The flag is operator state
on the `users` row (`users.flagged`), preserved across kind-0 re-projection, and it **never touches funds or
escrow**. Flagging a pubkey we hold no profile for still works (a bare identity row is created to carry the flag).

Note: removal is at the next read (the catalog/board/profile read live from the DB); a live board already open
keeps the stale card until reload. The deletion of user-published content the author themselves requests is
handled separately by NIP-09 (a kind-5 deletion removes the same-author events it references, and a deleted
kind-0 erases the projected profile).

## Log in as admin

1. **Get your account's 64-HEX pubkey** (not the npub). Either:
   - convert your npub: `bin/rails runner 'puts Nostr::Bech32.decode("npub1…")[1]'`, or
   - sign in to the app once, then read it: `bin/rails runner 'puts User.order(:updated_at).last.pubkey'`.
2. In `.env`, set the allowlist (comma-separated for multiple operators):
   ```
   OPERATOR_PUBKEYS=<your-64-hex-pubkey>
   ```
   To exercise the whole dispute flow, also enable Tier-2 with any 64-hex key:
   ```
   ESCROW_TIER2_ARBITER_PRIVKEY=1111111111111111111111111111111111111111111111111111111111111111
   ```
3. **Restart** the server (`bin/dev`) — env vars load at boot.
4. Sign in normally (browser extension / remote signer / pasted nsec) as that account.
5. Visit `http://localhost:3000/admin/disputes`.

## Seed a dispute to rule (so the queue isn't empty)

Open `bin/rails console` and paste:

```ruby
order = Order.create!(
  entry_point: Orders::EntryPoints::CATALOG_ORDER, current_state: Orders::States::AWAITING_FUNDING,
  tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000,
  listing_coordinate: "30402:#{SecureRandom.hex(32)}:demo", mint_url: "http://127.0.0.1:3338",
  dedupe_key: SecureRandom.hex(16), funding_deadline_at: 1.hour.from_now,
  consumer_pubkey: SecureRandom.hex(32), provider_pubkey: SecureRandom.hex(32),
)
order.state_machine.transition_to!(Orders::States::FUNDED)
Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey, reason: "Work never delivered (demo)")
```

Reload `/admin/disputes`: the dispute appears with **Rule for provider** / **Rule for consumer** buttons.
Ruling only records the outcome on the dispute; the order settles to released/refunded later, when the winning
party's on-mint spend is observed (the operator never holds funds or keys).

## Run the automated tests

```
# operator gating + ruling action (no mint needed)
bin/rails test test/controllers/admin/disputes_controller_test.rb
bin/rails test test/services/orders/rule_dispute_test.rb

# end-to-end through the real order page + admin surface (needs the local nutshell mint up at :3338)
bin/rails test test/system/order_tier2_page_test.rb
```

> The local nutshell mint rate-limits (HTTP 429) under repeated runs; if the system tests skip or fail with a
> 429, give it a minute to cool down. Run one-off `bin/rails runner`/`console` with `RAILS_ENV=test` when you
> want the test DB (this app is Postgres-only; never create a sqlite file).
