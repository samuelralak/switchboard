# frozen_string_literal: true

require "test_helper"

module Catalog
	class ListingTest < ActiveSupport::TestCase
		test "tolerates absent and malformed tags without raising" do
			event = build_event(title: "Service", d: "svc")
			event.update_column(:tags, [ [ "title", "Service" ], "junk", [ "d" ], [ "l", "x", "ns.capability" ] ])

			listing = Catalog::Listing.new(event)

			assert_nothing_raised do
				assert_equal "Service", listing.title
				assert_equal "x", listing.capability
				assert_nil listing.price_amount
				listing.search_text
				listing.dom_id
			end
		end

		test "parses a NIP-99 integer price and rejects a malformed amount" do
			priced = build_event(title: "A", d: "a", extra_tags: [ [ "price", "2500", "sat" ] ])
			assert_equal 2500, Catalog::Listing.new(priced).price_amount

			mangled = build_event(title: "B", d: "b", extra_tags: [ [ "price", "0x10", "sat" ] ])
			assert_nil Catalog::Listing.new(mangled).price_amount
		end
	end
end
