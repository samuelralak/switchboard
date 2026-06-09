# frozen_string_literal: true

require "dry/configurable"

module NostrClient
	# Typed dry-configurable settings for the relay list and reconnection tuning.
	#
	#   NostrClient.configure { |c| c.relays = ["wss://relay.damus.io"] }
	#   NostrClient.configuration.relays # => ["wss://relay.damus.io"]
	class Configuration
		extend Dry::Configurable

		setting :relays, default: [].freeze, constructor: Types::Relays
		# R_op's AUTH-gated DM/inbox relays (NIP-17/59), distinct from the catalog ingest `relays`.
		setting :dm_relays, default: [].freeze, constructor: Types::Relays
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
		# An object responding to #sign(kind:, tags:, content:) -> signed event hash, used to
		# answer NIP-42 AUTH challenges (the R_op operational signer). nil = AUTH disabled.
		setting :auth_signer, default: nil
	end
end
