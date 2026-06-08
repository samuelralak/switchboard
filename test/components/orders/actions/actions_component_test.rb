# frozen_string_literal: true

require "test_helper"

module Orders
	module Actions
		class ActionsComponentTest < ViewComponent::TestCase
			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)

			test "an awaiting order offers the consumer the funding flow" do
				order = build_order

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='funding']"
				assert_text "Fund escrow"
			end

			test "a funded order offers the consumer release + refund" do
				order = funded(build_order)

				render_inline(ActionsComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='settlement']"
				assert_text "Release escrow"
				assert_text "Refund"
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
		end
	end
end
