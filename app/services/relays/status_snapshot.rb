# frozen_string_literal: true

module Relays
	# The relay connection statuses, handed across processes via Solid Cache (a shared DB): the relay:boot
	# process writes a { url => state } snapshot each reconcile tick, and the web process reads it to light up
	# the relays UI. Best-effort: a cold/expired/missing snapshot (relay:boot down, or dev's per-process
	# memory store) reads as empty and the UI falls back to "settled". State is stored as a STRING so it
	# survives any cache serializer (message_pack/json do not round-trip symbols).
	class StatusSnapshot
		extend Dry::Initializer

		KEY = "relays:status_snapshot"

		option :store, default: -> { Rails.cache }

		# +status+ is Manager#status: { url => { state:, subscriptions:, reconnect_attempts: } }.
		def write(status)
			store.write(KEY, status.transform_values { |entry| entry[:state].to_s }, expires_in: ttl)
		end

		def read = store.read(KEY) || {}

		private

		# A little longer than the reconcile interval, so the snapshot never expires between ticks.
		def ttl = NostrClient.configuration.reconcile_interval_seconds + 10
	end
end
