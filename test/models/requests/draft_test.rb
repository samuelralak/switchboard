# frozen_string_literal: true

require "test_helper"

module Requests
	class DraftTest < ActiveSupport::TestCase
		def tags_for(params)
			Draft.open_request(params, pubkey: "ab" * 32).event.tags
		end

		test "builds the request marker, capability, budget, and windows in publisher order" do
			tags = tags_for(
				title: "Diagnose an engine", description: "From a video.", capability: "diagnosis",
				budget: "5000", delivery_value: "24", delivery_unit: "hours", claim_value: "3", claim_unit: "days"
			)

			assert_includes tags, [ "t", OpenRequest.marker ]
			assert_includes tags, [ "l", "diagnosis", Catalog::Listing::CAPABILITY_NAMESPACE ]
			assert_includes tags, %w[price 5000 sat]
			assert_includes tags, %w[delivery_window 24h]
			assert_includes tags, %w[claim_window 3d]
		end

		test "the budget price tag carries no recurring frequency (a bounty is one fixed amount)" do
			price = tags_for(title: "T", budget: "5000").find { |t| t[0] == "price" }

			assert_equal %w[price 5000 sat], price # exactly three elements, no 4th frequency
		end

		test "omits the budget and windows when blank" do
			names = tags_for(title: "T").map(&:first)

			assert_not_includes names, "price"
			assert_not_includes names, "delivery_window"
			assert_not_includes names, "claim_window"
		end

		test "emits image and imeta tags for picked images" do
			tags = tags_for(title: "T", images: [ { url: "https://h/a.png", m: "image/png", x: "abc", dim: "800x450" } ])

			assert_includes tags, [ "image", "https://h/a.png" ]
			assert_includes tags, [ "imeta", "url https://h/a.png", "m image/png", "x abc", "dim 800x450" ]
		end

		test "collapses day windows to the microstandard suffix" do
			tags = tags_for(title: "T", delivery_value: "2", delivery_unit: "days", claim_value: "12", claim_unit: "hours")

			assert_includes tags, %w[delivery_window 2d]
			assert_includes tags, %w[claim_window 12h]
		end

		test "the draft round-trips through OpenRequest" do
			request = Draft.open_request({ title: "T", capability: "diagnosis", budget: "5000" }, pubkey: "ab" * 32)

			assert_equal "diagnosis", request.capability
			assert_equal 5000, request.budget_amount
		end
	end
end
