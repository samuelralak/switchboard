# Switchboard

A non-custodial Nostr marketplace. User keys stay in the browser (NIP-07/46) and sign everything
client-side; the Rails runtime holds only its own low-privilege operational key (R_op) and never a
user secret or funds.

## Requirements

- Ruby 4.0.1 (see `.ruby-version`)
- PostgreSQL
- Rails 8.1

JavaScript is served through importmap and styles through Tailwind, so there is no Node build step.

## Setup

```bash
bundle install
cp .env.example .env      # then fill in values (see Configuration)
bin/rails db:prepare      # creates + migrates the primary, cache, queue, and cable databases
```

## Configuration

Local development and test configuration is loaded from `.env` by `dotenv-rails` (`.env` is
gitignored; `.env.example` is the committed, secret-free template). In production, provision these
as real environment variables (the platform's config vars / secrets) or via Rails credentials.

| Variable | Purpose |
| --- | --- |
| `CANONICAL_ORIGIN` | Absolute origin the NIP-98 sign-in is verified against (e.g. `https://app.example`). REQUIRED in production; a localhost default breaks auth. |
| `R_OP_PRIVATE_KEY` | The R_op operational key (64-char hex). Optional (AUTH-gated relays stay off without it). See below. |
| `ESCROW_MINT_ALLOWLIST` | Comma-separated Cashu mint URLs trusted for escrow. The production money path needs at least one; empty disables ordering. |
| `ESCROW_TIER2_ARBITER_PRIVKEY` | The platform's dedicated Cashu secp256k1 arbiter key (64-hex). Optional; blank disables Tier-2 mediated escrow. |
| `OPERATOR_PUBKEYS` | Comma-separated 64-hex Nostr pubkeys allowed onto the admin surface. Empty = closed. |
| `DATABASE_URL` / `DATABASE_PASSWORD` | Postgres connection for production (the primary + cache/queue/cable databases). |

Relay seeds are configured per-environment in `config/relays.yml`, not via an env var.

### The R_op operational key

R_op is the runtime's own low-privilege Nostr identity (never a user key, never holds funds). It
does two things:

1. Answers NIP-42 AUTH so the relay client can read and write AUTH-gated relays (e.g. the NIP-17 DM
   inbox).
2. Signs R_op's own events: its kind-10050 DM relay list, NIP-89 handler announcement, and the
   opaque escrow-coordination wraps.

The key is read from `R_OP_PRIVATE_KEY` and is touched only in `Operational::Signer` (private
reader, never logged). Generate one and add it to `.env`:

```bash
bin/rails runner 'puts Nostr::Keygen.new.generate_key_pair.private_key'
# add the printed 64-hex value to .env as: R_OP_PRIVATE_KEY=...
```

Nothing breaks without it: the app boots and catalog ingest uses public relays that need no AUTH.
NIP-42 AUTH activates automatically on the next boot once the key is present
(`Operational::Signer.configured?`).

## Running

```bash
bin/dev
```

`bin/dev` runs the processes in `Procfile.dev`:

- `web` — the Rails server
- `css` — Tailwind watch
- `jobs` — the Solid Queue worker
- `relay` — `bin/rails relay:boot`, the persistent relay connection that subscribes to the catalog
  and ingests events

## Tests

```bash
bin/rails test        # full suite
bundle exec rubocop   # lint
```

## Architecture notes

- **Non-custodial.** User keys never reach the server; signing happens in the browser. The runtime
  re-verifies signed events and relays them.
- **Persistence.** PostgreSQL, with Solid Cache, Solid Queue, and Solid Cable each on their own
  database.
- **Crypto.** A hand-rolled, vector-verified NIP-44 v2 module (`lib/nip44.rb`) underpins NIP-17/59
  private messaging and gift wraps.
- **Services.** Business logic lives in thin `BaseService` objects (dry-rb) that return on success
  and raise on failure.
