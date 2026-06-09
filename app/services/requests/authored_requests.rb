# frozen_string_literal: true

module Requests
	# The signed-in poster's own open requests for the My-requests view: their conforming request-marked
	# kind-30402 events, newest first. The ingest keeps exactly one event per coordinate (Events::Upsert
	# destroys the superseded one), so there is no per-coordinate de-duplication to do here. Unlike the
	# public Requests::Search this keeps WITHDRAWN (inactive) requests, so the poster can re-post them.
	# Mirrors Catalog::ProviderListings on the demand side.
	class AuthoredRequests < BaseService
		option :pubkey, type: Types::Strict::String

		def call
			own_requests.recent.map { |event| OpenRequest.new(event) }.select(&:conforms?)
		end

		private

		# The poster's own request-marked classified events (the marker include keeps service listings off
		# My-requests); conforms? is the authoritative request filter.
		def own_requests
			Event.classified.by_author(pubkey).with_tag("t", OpenRequest.marker)
		end
	end
end
