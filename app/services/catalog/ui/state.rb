# frozen_string_literal: true

module Catalog
	module Ui
		# Render state for the catalog, shared by the page render and the live broadcast
		# so both use the same stream, grid target, and partial.
		class State
			STREAM      = "catalog"
			GRID_TARGET = "catalog_listings"
			PARTIAL     = "catalog/listing"

			# One listing card, broadcast by Catalog::Ui::Update.
			Card = Data.define(:listing, :stream, :grid_target, :partial) do
				def card_id = listing.dom_id
				def locals = { listing: }
			end

			# The catalog grid for the page render.
			Grid = Data.define(:listings, :query, :stream, :grid_target, :partial) do
				def size = listings.size
				def never_ingested? = listings.empty? && query.blank?
				def no_matches? = listings.empty? && query.present?
			end

			def self.card(event:)
				Card.new(
					listing: Listing.new(event),
					stream: STREAM,
					grid_target: GRID_TARGET,
					partial: PARTIAL
				)
			end

			def self.grid(query: nil)
				Grid.new(
					listings: Catalog::Search.call(query:),
					query:,
					stream: STREAM,
					grid_target: GRID_TARGET,
					partial: PARTIAL
				)
			end
		end
	end
end
