# frozen_string_literal: true

require "test_helper"

module Catalog
	class DraftTest < ActiveSupport::TestCase
		test "builds a conforming, env-marked listing from automated params" do
			listing = Catalog::Draft.listing({
				"title" => "Summarize a thread", "description" => "Tight summaries.",
				"capability" => "summarize", "price" => "120", "fulfillment" => "automated",
				"endpoint" => "https://api.example.com/fulfill"
			}, pubkey: "a" * 64)

			assert_equal "Summarize a thread", listing.title
			assert_equal "Tight summaries.", listing.description
			assert_equal "summarize", listing.capability
			assert_equal 120, listing.price_amount
			assert_equal "automated", listing.fulfillment
			assert_equal "https://api.example.com/fulfill", listing.endpoint
			assert_predicate listing, :conforms?
		end

		test "emits the capability label under the canonical NIP-32 namespace" do
			tags = Catalog::Draft.new("capability" => "translate").tags
			l_tag = tags.find { |t| t[0] == "l" }

			assert_equal [ "l", "translate", Catalog::Listing::CAPABILITY_NAMESPACE ], l_tag
		end

		test "emits the marker tag in the publisher position: after title, before the capability label and price" do
			names = Catalog::Draft.new("capability" => "translate", "price" => "10").tags.map(&:first)

			assert_equal %w[d title t], names.first(3)
			assert_operator names.index("t"), :<, names.index("l")
			assert_operator names.index("t"), :<, names.index("price")
		end

		test "emits the NIP-99 per-hour frequency in the price tag, omitting it for per-request" do
			per_hour = Catalog::Draft.new("price" => "50000", "price_frequency" => "hour").tags.find { |t| t[0] == "price" }
			assert_equal %w[price 50000 sat hour], per_hour

			per_request = Catalog::Draft.new("price" => "50000").tags.find { |t| t[0] == "price" }
			assert_equal %w[price 50000 sat], per_request
		end

		test "collapses a manual delivery window value + unit into the microstandard string" do
			hours = Catalog::Draft.listing({ fulfillment: "manual", delivery_value: "24", delivery_unit: "hours" })
			days  = Catalog::Draft.listing({ fulfillment: "manual", delivery_value: "3", delivery_unit: "days" })

			assert_equal "24h", hours.delivery_window
			assert_equal "3d", days.delivery_window
		end

		test "omits the mode-specific tag that does not match the fulfillment mode" do
			automated = Catalog::Draft.listing({ fulfillment: "automated", delivery_value: "24", endpoint: "https://x.test" })
			manual    = Catalog::Draft.listing({ fulfillment: "manual", delivery_value: "24", endpoint: "https://x.test" })

			assert_nil automated.delivery_window
			assert_equal "https://x.test", automated.endpoint
			assert_nil manual.endpoint
			assert_equal "24h", manual.delivery_window
		end

		test "serializes input_schema with name, label, attachment type, and a boolean required" do
			rows = [
				{ "name" => "source_text", "label" => "Source text", "type" => "longtext", "required" => "true" },
				{ "label" => "Attach the file", "type" => "attachment" }
			]
			listing = Catalog::Draft.listing({ "schema" => rows })

			assert_equal(
				[
					{ name: "source_text", label: "Source text", type: "longtext", required: true },
					{ name: "attach_the_file", label: "Attach the file", type: "attachment", required: false }
				],
				listing.input_schema
			)
		end

		test "drops blank schema rows and tolerates string or symbol keys" do
			rows = [ { name: "", label: "" }, { label: "Kept", type: "text" } ]
			listing = Catalog::Draft.listing({ schema: rows })

			assert_equal 1, listing.input_schema.size
			assert_equal "Kept", listing.input_schema.first[:label]
		end

		test "reads back every supplied image as an image tag" do
			listing = Catalog::Draft.listing({ "images" => [ "https://host/a.png", "https://host/b.png", "" ] })

			assert_equal [ "https://host/a.png", "https://host/b.png" ], listing.images
		end

		test "emits an image tag plus NIP-92 imeta for each picked image, cover first" do
			images = [
				{ "url" => "https://host/a.png", "m" => "image/png", "x" => "abc123", "dim" => "800x450" },
				{ "url" => "https://host/b.jpg", "m" => "image/jpeg", "x" => "def456", "dim" => "1024x768" }
			]
			listing = Catalog::Draft.listing({ "images" => images })

			assert_equal [ "https://host/a.png", "https://host/b.jpg" ], listing.images
			assert_equal "https://host/a.png", listing.image # cover = first
			assert_equal({ url: "https://host/a.png", m: "image/png", x: "abc123", dim: "800x450" }, listing.image_meta("https://host/a.png"))
			assert_equal({ url: "https://host/b.jpg", m: "image/jpeg", x: "def456", dim: "1024x768" }, listing.image_meta("https://host/b.jpg"))
		end

		test "drops images that have no url and omits imeta when no metadata is present" do
			listing = Catalog::Draft.listing({ "images" => [ { "url" => "https://host/a.png" }, { "m" => "image/png" } ] })

			assert_equal [ "https://host/a.png" ], listing.images
			assert_empty listing.image_meta("https://host/a.png") # url-only image carries no imeta tag
		end

		test "defaults to an untitled, still-conforming listing when empty" do
			listing = Catalog::Draft.listing({})

			assert_equal "Untitled service", listing.title
			assert_predicate listing, :conforms?
			assert_empty listing.input_schema
		end
	end
end
