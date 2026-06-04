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

		test "parses the input_schema tag into fields, tolerating malformed or absent JSON" do
			fields = [ { label: "Source text", type: "longtext", required: true } ]
			present = build_event(title: "S", d: "s1", extra_tags: [ [ "input_schema", fields.to_json ] ])
			assert_equal fields, Catalog::Listing.new(present).input_schema

			malformed = build_event(title: "S", d: "s2", extra_tags: [ [ "input_schema", "{bad" ] ])
			assert_empty Catalog::Listing.new(malformed).input_schema
			assert_empty Catalog::Listing.new(build_event(title: "S", d: "s3")).input_schema
		end
	end
end
