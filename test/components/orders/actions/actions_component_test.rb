# frozen_string_literal: true

require "test_helper"

module Orders
	module Actions
		class ActionsComponentTest < ViewComponent::TestCase
			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)

			test "an awaiting order offers the consumer the funding flow" do
				order = build_order

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='funding'][data-funding-tier-value='#{Orders::Tiers::TIER1_HTLC}']"
				assert_text "Fund escrow"
			end

			test "an awaiting tier-2 order passes the tier + platform arbiter to the funding controller" do
				order = build_order(tier: Orders::Tiers::TIER2_ARBITER)

				with_arbiter_key { render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey))) }

				assert_selector "[data-controller='funding'][data-funding-tier-value='#{Orders::Tiers::TIER2_ARBITER}']"
				assert_selector "[data-funding-arbiter-value='#{platform_arbiter_pubkey}']"
				assert_text "platform arbiter"
			end

			test "a funded order offers the consumer release + refund" do
				order = funded(build_order)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='settlement']"
				assert_text "Release escrow"
				assert_text "Refund"
			end

			test "a delivered + released funded order shows the consumer awaiting redemption, no release button" do
				order = funded(build_order)
				Orders::MarkDelivered.call(order:, delivery_event_id: SecureRandom.hex(32),
					delivered_at: Time.current.to_i, content_hash: SecureRandom.hex(32))
				Orders::MarkReleased.call(order:, reveal_event_id: SecureRandom.hex(32), released_at: Time.current.to_i)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_text "released the escrow"
				assert_text "Refund"
				assert_no_text "Release escrow"
			end

			test "a funded order offers the provider verify + redeem" do
				order = funded(build_order)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_text "Verify funds"
				assert_text "Redeem"
			end

			test "a funded order offers the provider a deliver panel" do
				order = funded(build_order)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_selector "[data-controller='order-result']"
				assert_text "Submit delivery"
			end

			test "a non-party sees no actions" do
				order = funded(build_order)

				render_inline(ActionsComponent.new(order:, viewer: viewer("f" * 64)))

				assert_no_selector "[data-controller]"
			end

			test "a funded tier-2 order offers the consumer release (tiered) + a dispute affordance" do
				order = fund_tier2_order

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='settlement'][data-settlement-tier-value='#{Orders::Tiers::TIER2_ARBITER}']"
				assert_text "Release escrow"
				assert_selector "form[action='#{url.order_dispute_path(order)}']"
				assert_text "Open a dispute"
			end

			test "a funded tier-2 order gives the provider the arbiter pubkey + verify/redeem + a dispute affordance" do
				order = fund_tier2_order

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_selector "[data-settlement-arbiter-pubkey-value='#{order.lock.arbiter_pubkey}']"
				assert_text "Verify funds"
				assert_text "Redeem"
				assert_text "Open a dispute"
			end

			test "a funded tier-1 order shows no dispute affordance" do
				render_inline(ActionsComponent.new(order: funded(build_order), viewer: viewer(build_order.consumer_pubkey)))

				assert_no_text "Open a dispute"
			end

			test "a funded tier-2 order whose release is authorized hides the dispute affordance" do
				order = fund_tier2_order
				order.create_release!(reveal_event_id: SecureRandom.hex(32), released_at: Time.current)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_no_text "Open a dispute"
			end

			test "a dispute ruled for the provider gives the provider the arbiter-cosigned claim" do
				order = ruled_tier2(Orders::DisputeStatuses::RULED_FOR_PROVIDER)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_text "Claim with arbiter co-signature"
				assert_selector "[data-settlement-arbiter-url-value]"
				assert_selector "[data-action='settlement#disputeRedeem']", visible: :all
			end

			test "a dispute ruled for the consumer gives the consumer the claim and the losing provider nothing" do
				order = ruled_tier2(Orders::DisputeStatuses::RULED_FOR_CONSUMER)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))
				assert_text "Claim with arbiter co-signature"

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.provider_pubkey)))
				assert_no_selector "[data-controller]"
			end

			test "a terminal order shows no actions to either party" do
				order = funded(build_order)
				order.state_machine.transition_to!(Orders::States::REFUNDED)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_no_selector "[data-controller]"
			end

			private

			def funded(order)
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order
			end

			# A funded tier-2 order moved to disputed with a ruled dispute at the given status.
			def ruled_tier2(status)
				order = fund_tier2_order
				Orders::Transition.call(order:, to: Orders::States::DISPUTED)
				order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status:)

				order
			end

			def url = Rails.application.routes.url_helpers
		end
	end
end
