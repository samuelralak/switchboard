# frozen_string_literal: true

require "dry/configurable"

module NostrClient
	# Typed dry-configurable settings: the relay lists, plus reconnect/keepalive and relay-ingest tuning.
	#
	#   NostrClient.configure { |c| c.relays = ["wss://relay.damus.io"] }
	#   NostrClient.configuration.relays # => ["wss://relay.damus.io"]
	class Configuration
		extend Dry::Configurable

		setting :relays, default: [].freeze, constructor: Types::Relays
		# R_op's AUTH-gated DM/inbox relays (NIP-17/59), distinct from the catalog ingest `relays`.
		setting :dm_relays, default: [].freeze, constructor: Types::Relays
		# Fixed public indexers for the read-only one-shot fetch of a user's NIP-65 (kind:10002) list on login.
		setting :indexer_relays, default: [].freeze, constructor: Types::Relays
		# Past this many failed reconnects a relay is logged as "degraded" (a single WARN), but it is
		# NEVER permanently abandoned: backoff just settles at max_reconnect_delay_seconds and keeps trying.
		setting :max_reconnect_attempts, default: 10, constructor: Types::Coercible::Integer
		setting :reconnect_delay_seconds, default: 2, constructor: Types::Coercible::Integer
		# Ceiling for the exponential reconnect backoff, so a long outage settles at a steady retry rate.
		setting :max_reconnect_delay_seconds, default: 300, constructor: Types::Coercible::Integer
		setting :publish_timeout_seconds, default: 10, constructor: Types::Coercible::Integer
		# Keepalive: ping every ping_interval_seconds and force a reconnect if the PONG does not return
		# within pong_timeout_seconds, so a silent half-open socket is detected instead of looking healthy.
		setting :ping_interval_seconds, default: 30, constructor: Types::Coercible::Integer
		setting :pong_timeout_seconds, default: 10, constructor: Types::Coercible::Integer
		# Relay-ingest tuning. The desired relay set adds at most max_relays distinct user WRITE-relay urls on
		# top of the seeds; the reconcile re-derives that set from the DB every reconcile_interval_seconds.
		setting :max_relays, default: 50, constructor: Types::Coercible::Integer
		# Per-user dial budget: at most this many of a single user's WRITE relays are folded into the ingest
		# (NIP-65 guides 2-4 write relays; 5 is the ecosystem ceiling). The full list is still stored; this
		# only bounds how many we DIAL, so one user cannot dominate the global max_relays budget.
		setting :max_write_relays_per_user, default: 5, constructor: Types::Coercible::Integer
		setting :reconcile_interval_seconds, default: 45, constructor: Types::Coercible::Integer
		# Flap-exclusion: a relay must be undesired for this many CONSECUTIVE reconcile ticks before it is
		# evicted, so a transient dip in active sessions does not thrash connections.
		setting :teardown_grace_ticks, default: 2, constructor: Types::Coercible::Integer
		# A live subscription pulls up to subscription_limit events; a newly added relay's one-shot backlog
		# pull is bounded by backfill_limit, de-duplicated once per (subscription, url) for backfill_flag_ttl.
		setting :subscription_limit, default: 500, constructor: Types::Coercible::Integer
		setting :backfill_limit, default: 500, constructor: Types::Coercible::Integer
		setting :backfill_flag_ttl_seconds, default: 30.days.to_i, constructor: Types::Coercible::Integer
		# A one-shot Relays::FetchEvents waits this long for each relay to EOSE before giving up.
		setting :fetch_timeout_seconds, default: 5, constructor: Types::Coercible::Integer
		# An object responding to #sign(kind:, tags:, content:) -> signed event hash, used to
		# answer NIP-42 AUTH challenges (the R_op operational signer). nil = AUTH disabled.
		setting :auth_signer, default: nil
	end
end
