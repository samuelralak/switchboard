# frozen_string_literal: true

module Catalog
	# The signed-in provider's own service listings for the studio's My-listings view: their conforming
	# kind-30402 events, newest first. The ingest keeps exactly one event per coordinate (Events::Upsert
	# destroys the superseded one), so there is no per-coordinate de-duplication to do here. Unlike the
	# public Catalog::Search this keeps INACTIVE (unpublished) listings, so the provider can manage them.
	class ProviderListings < BaseService
		option :pubkey, type: Types::Strict::String

		def call
			Event.classified.where(pubkey:).recent.map { |event| Listing.new(event) }.select(&:conforms?)
		end
	end
end
