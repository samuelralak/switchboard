# frozen_string_literal: true

module Attestation
	# Attests a kind-30402 a provider reports publishing (a service or an open request): verifies they own it
	# and it conforms, stores it, then issues the attestation. The interim trigger (a session-authed report);
	# the eventual one observes the listing fee via relay-ingest. Returns the issued label, or nil.
	class Attest < BaseService
		option :event_data, type: Types::Strict::Hash
		option :reporter_pubkey, type: Types::Strict::String
		option :manager, default: -> { NostrClient.manager }

		def call
			return unless Policy.issuing?
			return unless owned_by_reporter?

			stored = store
			return unless stored && conforming?(stored)

			Issue.call(event: stored, manager:)
		end

		private

		# A provider can only attest their OWN listing: the reported event's author must be the session user.
		def owned_by_reporter?
			event_data["pubkey"] == reporter_pubkey
		end

		# Verify + store the reported event (it would also arrive via relay-ingest; this removes the race), and
		# return the stored Event. Catalog::Ingest returns :duplicate when we already hold it, so fall back to a
		# lookup by id. Raises InvalidEventError on a bad/forged event (the controller renders that as a 4xx).
		def store
			result = Catalog::Ingest.call(event_data:)
			result.is_a?(Event) ? result : Event.find_by(event_id: event_data["id"])
		end

		# A conforming Switchboard publication is a kind-30402 carrying our env-scoped marker, whether a service
		# listing or an open request. Both are attested the same way.
		def conforming?(event)
			return false unless event.kind == Events::Kinds::CLASSIFIED

			Catalog::Listing.new(event).conforms? || Requests::OpenRequest.new(event).conforms?
		end
	end
end
