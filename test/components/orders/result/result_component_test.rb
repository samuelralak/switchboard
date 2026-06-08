# frozen_string_literal: true

require "test_helper"

module Orders
	module Result
		class ResultComponentTest < ViewComponent::TestCase
			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)

			test "the consumer sees the result panel once the order is funded" do
				order = funded(build_order)

				render_inline(ResultComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='order-result']"
				assert_text "data out · delivered result"
			end

			test "the consumer sees no result panel before funding" do
				order = build_order # awaiting_funding

				render_inline(ResultComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_no_selector "[data-controller='order-result']"
			end

			test "the provider does not see the consumer result panel" do
				order = funded(build_order)

				render_inline(ResultComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_no_selector "[data-controller='order-result']"
			end

			private

			def funded(order)
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order
			end
		end
	end
end
