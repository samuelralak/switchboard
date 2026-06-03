# frozen_string_literal: true

module Sessions
	# Single-use gate for stateless NIP-98 auth: rejects any event id seen before, so a
	# captured token cannot be replayed within the freshness window. Keyed on the NIP-01
	# event id (bound to the signature) via an atomic write-if-absent cache entry.
	class ReplayGuard < BaseService
		# Cover the full acceptance band (the ±TIMESTAMP_WINDOW = 2x span) plus skew, so a
		# still-fresh token can never outlive its single-use entry. Derived to avoid drift.
		TTL = (Events::VerifyHttpAuth::TIMESTAMP_WINDOW * 2) + 10 # seconds

		option :event_id, type: Types::Strict::String
		option :store, default: -> { Rails.cache } # injectable; Rails.cache is the null store in test

		def call
			reserved = store.write("nip98:seen:#{event_id}", true, expires_in: TTL, unless_exist: true)
			raise AuthenticationError, "replay" unless reserved
		end
	end
end
