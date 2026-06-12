# frozen_string_literal: true

require "test_helper"

module Catalog
	class ListingTest < ActiveSupport::TestCase
		test "tolerates absent and malformed tags without raising" do
			event = Event.new(tags: [ %w[title Service], "junk", [ "d" ], [ "l", "x", "ns.capability" ] ])

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
			priced = build_event(title: "A", d: "a", extra_tags: [ %w[price 2500 sat] ])
			assert_equal 2500, Catalog::Listing.new(priced).price_amount

			mangled = build_event(title: "B", d: "b", extra_tags: [ %w[price 0x10 sat] ])
			assert_nil Catalog::Listing.new(mangled).price_amount
		end

		test "reads the NIP-99 recurring frequency: per-hour vs per-request" do
			per_hour = Catalog::Listing.new(build_event(title: "Hr", d: "hr", extra_tags: [ %w[price 50000 sat hour] ]))
			assert_equal "hour", per_hour.price_frequency
			assert_predicate per_hour, :per_hour?
			assert_equal "sat / hr", per_hour.price_suffix

			per_request = Catalog::Listing.new(build_event(title: "Req", d: "req", extra_tags: [ %w[price 50000 sat] ]))
			assert_nil per_request.price_frequency
			assert_not per_request.per_hour?
			assert_equal "sat", per_request.price_suffix
		end

		test "parses input_schema fields with name + label, tolerating malformed or absent JSON" do
			fields = [ { "name" => "src", "label" => "Source text", "type" => "longtext", "required" => true } ]
			present = build_event(title: "S", d: "s1", extra_tags: [ [ "input_schema", fields.to_json ] ])
			expected = [ { name: "src", label: "Source text", type: "longtext", required: true } ]
			assert_equal expected, Catalog::Listing.new(present).input_schema

			malformed = build_event(title: "S", d: "s2", extra_tags: [ [ "input_schema", "{bad" ] ])
			assert_empty Catalog::Listing.new(malformed).input_schema
			assert_empty Catalog::Listing.new(build_event(title: "S", d: "s3")).input_schema
		end

		test "input_schema name falls back to a slug of the label when absent" do
			fields = [ { "label" => "Thread URL or note IDs", "type" => "url" } ]
			event = build_event(title: "S", d: "s4", extra_tags: [ [ "input_schema", fields.to_json ] ])

			field = Catalog::Listing.new(event).input_schema.first
			assert_equal "thread_url_or_note_ids", field[:name]
			assert_equal "Thread URL or note IDs", field[:label]
		end

		test "marker is environment-scoped, and conforms? checks it" do
			assert_equal "switchboard-service-test", Catalog::Listing.marker

			conforming = build_event(title: "S", d: "c1", extra_tags: [ [ "t", Catalog::Listing.marker ] ])
			assert_predicate Catalog::Listing.new(conforming), :conforms?

			prod_marker = build_event(title: "S", d: "c2", extra_tags: [ %w[t switchboard-service] ])
			assert_not_predicate Catalog::Listing.new(prod_marker), :conforms?
		end

		test "reads the endpoint and delivery_window microstandard tags" do
			tags = [ %w[endpoint https://api.test/qa], %w[delivery_window 24h] ]
			listing = Catalog::Listing.new(build_event(title: "S", d: "m1", extra_tags: tags))

			assert_equal "https://api.test/qa", listing.endpoint
			assert_equal "24h", listing.delivery_window
		end

		test "reads all image tags, with the first as the cover" do
			tags = [ %w[image https://host/a.png], %w[image https://host/b.png] ]
			listing = Catalog::Listing.new(build_event(title: "S", d: "m2", extra_tags: tags))

			assert_equal [ "https://host/a.png", "https://host/b.png" ], listing.images
			assert_equal "https://host/a.png", listing.image
		end

		test "reads NIP-92 imeta metadata for the matching image url" do
			imeta = [ "imeta", "url https://host/a.png", "m image/png", "dim 800x450", "blurhash LKO2" ]
			tags = [ %w[image https://host/a.png], imeta ]
			listing = Catalog::Listing.new(build_event(title: "S", d: "m3", extra_tags: tags))
			meta = { url: "https://host/a.png", m: "image/png", dim: "800x450", blurhash: "LKO2" }

			assert_equal meta, listing.image_meta("https://host/a.png")
			assert_empty listing.image_meta("https://host/missing.png")
		end

		test "serialized-JSON content never renders raw; it falls back to the summary tag" do
			array_blob = Event.new(
				content: '[["id","30402:abc"],["title","x"]]',
				tags: [ [ "title", "Sound Coffee" ], [ "summary", "Single-origin pour-over, delivered." ] ]
			)
			object_blob = Event.new(content: '{"id":"abc","kind":30402}', tags: [ [ "title", "X" ], [ "summary", "Clean blurb." ] ])

			array_listing = Catalog::Listing.new(array_blob)
			assert_equal "Single-origin pour-over, delivered.", array_listing.description
			assert_equal "Single-origin pour-over, delivered.", array_listing.summary
			assert_not_includes array_listing.search_text, "30402", "the raw JSON never reaches the search haystack"
			assert_equal "Clean blurb.", Catalog::Listing.new(object_blob).description
		end

		test "a Markdown description that opens with a link is not mistaken for JSON" do
			event = Event.new(content: "[my site](https://x.test) handles the rest", tags: [ [ "title", "X" ] ])

			assert_equal "[my site](https://x.test) handles the rest", Catalog::Listing.new(event).description
		end
	end
end
