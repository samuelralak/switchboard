# frozen_string_literal: true

require "test_helper"

module Requests
	module RequestForm
		# The composer's escrow-type opt-in: offered only when the platform arbiter is provisioned, carries the
		# Tier-2 cap for the client-side budget guard, and pre-selects the poster's current tier on edit.
		class RequestFormComponentTest < ViewComponent::TestCase
			def request(extra_tags: [], **)
				event = build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
				OpenRequest.new(event)
			end

			test "offers both escrow-type radios when the platform arbiter is provisioned" do
				with_arbiter_key do
					render_inline(RequestFormComponent.new(request: request))
				end

				assert_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER1_HTLC}']", visible: :all
				assert_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}']", visible: :all
			end

			test "hides the escrow-type choice entirely when no arbiter is configured" do
				render_inline(RequestFormComponent.new(request: request))

				assert_no_selector "input[name='escrow_tier']", visible: :all
			end

			test "the mediated radio carries the tier-2 cap so the composer can reject an over-budget request" do
				with_arbiter_key do
					render_inline(RequestFormComponent.new(request: request))
				end

				cap_radio = "input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}'][data-cap='#{Orders::Policy.tier2_max_order_sats}']"
				assert_selector cap_radio, visible: :all
			end

			test "defaults to standard escrow on a new request" do
				with_arbiter_key do
					render_inline(RequestFormComponent.new(request: request))
				end

				assert_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER1_HTLC}'][checked]", visible: :all
				assert_no_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}'][checked]", visible: :all
			end

			test "pre-selects the poster's mediated choice on edit" do
				req = request(extra_tags: [ [ "escrow_tier", Orders::Tiers::TIER2_ARBITER ] ])

				with_arbiter_key do
					render_inline(RequestFormComponent.new(request: req))
				end

				assert_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}'][checked]", visible: :all
				assert_no_selector "input[name='escrow_tier'][value='#{Orders::Tiers::TIER1_HTLC}'][checked]", visible: :all
			end
		end
	end
end
