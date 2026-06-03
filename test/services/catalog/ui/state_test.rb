# frozen_string_literal: true

require "test_helper"

module Catalog
	module Ui
		class StateTest < ActiveSupport::TestCase
			test "card wraps the event in a listing with the broadcast wiring" do
				card = Catalog::Ui::State.card(event: build_event(title: "Logo design"))

				assert_equal "catalog", card.stream
				assert_equal "catalog_listings", card.grid_target
				assert_equal "catalog/listing", card.partial
				assert_equal "Logo design", card.listing.title
				assert_equal card.listing.dom_id, card.card_id
				assert_equal({ listing: card.listing }, card.locals)
			end

			test "grid composes the searched listings with the page wiring" do
				build_event(title: "Logo design", d: "logo")
				build_event(title: "Tax filing", d: "tax")

				grid = Catalog::Ui::State.grid(query: "logo")

				assert_equal "catalog", grid.stream
				assert_equal "catalog_listings", grid.grid_target
				assert_equal "catalog/listing", grid.partial
				assert_equal [ "Logo design" ], grid.listings.map(&:title)
				assert_equal 1, grid.size
				assert_not grid.never_ingested?
			end

			test "grid is never_ingested when empty and unfiltered" do
				grid = Catalog::Ui::State.grid(query: "")

				assert_equal 0, grid.size
				assert grid.never_ingested?
			end

			test "grid reports no_matches when a query filters everything out" do
				build_event(title: "Logo design", d: "logo")

				grid = Catalog::Ui::State.grid(query: "nonexistent")

				assert_equal 0, grid.size
				assert grid.no_matches?
				assert_not grid.never_ingested?
			end
		end
	end
end
