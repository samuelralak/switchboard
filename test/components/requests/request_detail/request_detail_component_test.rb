# frozen_string_literal: true

require "test_helper"

module Requests
	module RequestDetail
		class RequestDetailComponentTest < ViewComponent::TestCase
			def request(extra_tags: [], **)
				event = build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
				OpenRequest.new(event)
			end

			test "renders the need, budget, windows, and the funded-bounty note" do
				req = request(title: "Diagnose an engine", content: "## Scope\n\nFrom a **video**.",
											extra_tags: [ %w[price 5000 sat], %w[claim_window 3d], %w[delivery_window 24h] ])

				render_inline(RequestDetailComponent.new(request: req))

				assert_selector ".markdown h2", text: "Scope"
				assert_text "open request"
				assert_text "budget"
				assert_text "5,000"
				assert_text "claim within 3d"
				assert_text "deliver in 24h"
				assert_text "funded bounty"
			end

			test "shows the claim CTA disabled (claiming lands with escrow)" do
				render_inline(RequestDetailComponent.new(request: request(extra_tags: [ %w[price 5000 sat] ])))

				assert_selector "button[disabled]", text: /Claim this request/
			end

			test "handles a request with no budget" do
				render_inline(RequestDetailComponent.new(request: request(title: "Need")))

				assert_text "No budget set"
			end
		end
	end
end
