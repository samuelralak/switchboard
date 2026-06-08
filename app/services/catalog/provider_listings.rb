# frozen_string_literal: true

module Catalog
	# The signed-in provider's own service listings for the studio's My-listings view: their conforming
	# kind-30402 events, newest first. The ingest keeps exactly one event per coordinate (Events::Upsert
	# destroys the superseded one), so there is no per-coordinate de-duplication to do here. Unlike the
	# public Catalog::Search this keeps INACTIVE (unpublished) listings, so the provider can manage them.
	class ProviderListings < BaseService
		option :pubkey, type: Types::Strict::String

		def call
			own_listings.recent.map { |event| Listing.new(event) }.select(&:conforms?)
		end

		private

		# The provider's own classified events, with open requests (same kind 30402, request marker) excluded
		# at the SQL layer so the demand board never bleeds into My-listings; conforms? is the authoritative filter.
		def own_listings
			Event.classified.by_author(pubkey).without_tag("t", Requests::OpenRequest.marker)
		end
	end
end
