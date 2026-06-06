# frozen_string_literal: true

require "test_helper"

module Requests
	class OpenRequestTest < ActiveSupport::TestCase
		# A conforming open-request event: a kind-30402 carrying the request marker.
		def request_event(extra_tags: [], **)
			build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
		end

		test "the marker is env-scoped, distinct from the service marker" do
			assert_equal "switchboard-request-test", OpenRequest.marker
			assert_not_equal Catalog::Listing.marker, OpenRequest.marker
		end

		test "reads title, brief, and capability" do
			event = request_event(title: "Diagnose an engine", content: "From a video.",
														 extra_tags: [ [ "l", "diagnosis", Catalog::Listing::CAPABILITY_NAMESPACE ] ])
			request = OpenRequest.new(event)

			assert_equal "Diagnose an engine", request.title
			assert_equal "From a video.", request.description
			assert_equal "diagnosis", request.capability
		end

		test "reads the budget from the NIP-99 price tag with a sat default" do
			request = OpenRequest.new(request_event(extra_tags: [ %w[price 5000 sat] ]))

			assert_predicate request, :budget?
			assert_equal 5000, request.budget_amount
			assert_equal "sat", request.budget_currency
		end

		test "has no budget when no price tag is present" do
			assert_not_predicate OpenRequest.new(request_event), :budget?
		end

		test "reads the claim and delivery windows" do
			request = OpenRequest.new(request_event(extra_tags: [ %w[claim_window 3d], %w[delivery_window 24h] ]))

			assert_equal "3d", request.claim_window
			assert_equal "24h", request.delivery_window
		end

		test "reads the cover image, all images, and imeta, dropping non-http urls" do
			request = OpenRequest.new(request_event(extra_tags: [
				[ "image", "https://h/a.png" ], [ "imeta", "url https://h/a.png", "m image/png", "dim 800x450" ],
				[ "image", "javascript:alert(1)" ], [ "image", "https://h/b.png" ]
			]))

			assert_equal "https://h/a.png", request.image # cover = first image tag (http only)
			assert_equal [ "https://h/a.png", "https://h/b.png" ], request.images # javascript: url dropped
			assert_equal({ url: "https://h/a.png", m: "image/png", dim: "800x450" }, request.image_meta("https://h/a.png"))
		end

		test "open? tracks the status tag" do
			assert_predicate OpenRequest.new(request_event), :open?
			assert_not_predicate OpenRequest.new(request_event(extra_tags: [ %w[status inactive] ])), :open?
		end

		test "conforms? requires the request marker" do
			assert_predicate OpenRequest.new(request_event), :conforms?
			assert_not_predicate OpenRequest.new(build_event), :conforms? # a plain listing, no request marker
		end

		test "dom_id is stable for a coordinate and prefixed for requests" do
			event = request_event(d: "abc")
			assert_equal OpenRequest.new(event).dom_id, OpenRequest.new(event).dom_id
			assert_match(/\Arequest_/, OpenRequest.new(event).dom_id)
		end
	end
end
