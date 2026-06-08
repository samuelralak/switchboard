# frozen_string_literal: true

require "test_helper"

module Requests
	module RequestDetail
		class RequestDetailComponentTest < ViewComponent::TestCase
			def request(extra_tags: [], **)
				event = build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
				OpenRequest.new(event)
			end

			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)

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

			test "shows the claim CTA disabled without a signed-in viewer" do
				render_inline(RequestDetailComponent.new(request: request(extra_tags: [ %w[price 5000 sat] ])))

				assert_selector "button[disabled]", text: /Claim this request/
				assert_no_selector "[data-controller='claim']"
			end

			test "an open whole-sat request offers a non-author the claim flow" do
				req = request(extra_tags: [ %w[price 5000 sat] ])

				render_inline(RequestDetailComponent.new(request: req, viewer: viewer("f" * 64)))

				assert_selector "[data-controller='claim']"
				assert_selector "button:not([disabled])", text: /Claim this request/
				assert_selector "input[name='order[coordinate]']", visible: :all
			end

			test "the author cannot claim their own request" do
				req = request(extra_tags: [ %w[price 5000 sat] ])

				render_inline(RequestDetailComponent.new(request: req, viewer: viewer(req.event.pubkey)))

				assert_selector "button[disabled]", text: /Claim this request/
				assert_no_selector "[data-controller='claim']"
			end

			test "a non-whole-sat request is not claimable" do
				req = request(extra_tags: [ %w[price 10 usd] ])

				render_inline(RequestDetailComponent.new(request: req, viewer: viewer("f" * 64)))

				assert_selector "button[disabled]", text: /Claim this request/
			end

			test "handles a request with no budget" do
				render_inline(RequestDetailComponent.new(request: request(title: "Need")))

				assert_text "No budget set"
			end
		end
	end
end
