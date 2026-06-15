# frozen_string_literal: true

require "test_helper"

module Requests
	module RequestCard
		class RequestCardComponentTest < ViewComponent::TestCase
			def request(extra_tags: [], **)
				event = build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
				OpenRequest.new(event)
			end

			test "renders the title, capability, budget, and an open pill, opening its drawer" do
				req = request(title: "Diagnose an engine",
											extra_tags: [ [ "l", "diagnosis", Catalog::Listing::CAPABILITY_NAMESPACE ], %w[price 5000 sat] ])

				render_inline(RequestCardComponent.new(request: req))

				assert_selector "button[command='show-modal'][commandfor='request-drawer-#{req.dom_id}']"
				assert_text "Diagnose an engine"
				assert_text "diagnosis"
				assert_text "open"
				assert_text "5,000"
			end

			test "emits the data-* contract the shared catalog controller filters and sorts on" do
				req = request(title: "Need", extra_tags: [ %w[price 7000 sat] ])

				render_inline(RequestCardComponent.new(request: req))

				assert_selector "[data-catalog-target='card'][data-price='7000']"
				assert_selector "[data-search]"
			end

			test "renders a cover image when present and hides the fallback placeholder" do
				req = request(extra_tags: [ %w[price 5000 sat], [ "image", "https://h/cover.png" ] ])
				render_inline(RequestCardComponent.new(request: req))

				assert_selector "img[src='https://h/cover.png']"
				assert_selector "[data-image-fallback-placeholder].hidden" # neutral placeholder is the fallback
			end

			test "shows the neutral placeholder slot when there is no image" do
				render_inline(RequestCardComponent.new(request: request(extra_tags: [ %w[price 5000 sat] ])))

				assert_no_selector "img"
				assert_selector "[data-image-fallback-placeholder]:not(.hidden)"
			end

			test "renders the claim window when present" do
				req = request(extra_tags: [ %w[price 5000 sat], %w[claim_window 3d] ])
				render_inline(RequestCardComponent.new(request: req))

				assert_text "claim in 3d"
			end

			# Guards the broadcast path: a card built without Attestation::Policy.mark must still emit the right
			# data-attested (Attestable resolves it live), so the client filter and badge work on streamed cards.
			test "data-attested reflects attestation live, without mark preloading" do
				labelled = request(title: "Vetted", extra_tags: [ %w[price 5000 sat] ])
				Attestation::Issue.call(event: labelled.event, manager: fake_manager)
				render_inline(RequestCardComponent.new(request: OpenRequest.new(labelled.event)))
				assert_selector "[data-attested='true']"

				render_inline(RequestCardComponent.new(request: request(title: "Plain", extra_tags: [ %w[price 5000 sat] ])))
				assert_selector "[data-attested='false']"
			end
		end
	end
end
