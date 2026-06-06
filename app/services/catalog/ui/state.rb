# frozen_string_literal: true

module Catalog
	module Ui
		# Render state for the catalog, shared by the page render and the live broadcast
		# so both use the same stream, grid target, and partial.
		class State
			STREAM         = "catalog"
			GRID_TARGET    = "catalog_listings"
			PARTIAL        = "catalog/listing"
			# The container the live broadcast appends a card's drawer into.
			DRAWER_TARGET  = "service-drawers"
			DRAWER_PARTIAL = "catalog/drawer"

			# One listing card (+ its drawer), broadcast by Catalog::Ui::Update.
			Card = Data.define(:listing, :stream, :grid_target, :partial) do
				def card_id = listing.dom_id
				# The removable drawer wrapper id (see catalog/_drawer.html.erb).
				def drawer_id = "service-drawer-#{listing.dom_id}-wrap"
				def drawer_target = DRAWER_TARGET
				def drawer_partial = DRAWER_PARTIAL
				def locals = { listing: }
			end

			# The catalog grid for the page render.
			Grid = Data.define(:listings, :query, :stream, :grid_target, :partial) do
				delegate :size, to: :listings
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
