# frozen_string_literal: true

require "test_helper"

module Orders
	module Result
		class ResultComponentTest < ViewComponent::TestCase
			def viewer(pubkey)
				Struct.new(:pubkey).new(pubkey)
			end

			test "the consumer sees the result panel once funded, decrypting with their own key against the provider" do
				order = funded(build_order)

				render_inline(ResultComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_selector "[data-controller='order-result'][data-order-result-own-value='#{order.consumer_pubkey}']"
				assert_selector "[data-order-result-provider-value='#{order.provider_pubkey}']" # the trust anchor
				assert_text "data out · delivered result"
			end

			test "the provider sees their own delivery once delivered, decrypting their self-copy" do
				order = funded(build_order)
				deliver(order)

				render_inline(ResultComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_selector "[data-controller='order-result'][data-order-result-own-value='#{order.provider_pubkey}']"
				assert_selector "[data-order-result-provider-value='#{order.provider_pubkey}']" # author must be the provider
				assert_text "your delivery"
			end

			test "the consumer sees no result panel before funding" do
				order = build_order # awaiting_funding

				render_inline(ResultComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_no_selector "[data-controller='order-result']"
			end

			test "the provider sees no panel before they have delivered" do
				order = funded(build_order)

				render_inline(ResultComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_no_selector "[data-controller='order-result']"
			end

			private

			def funded(order)
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order
			end

			# the panel only checks delivery presence, so the assertion values are immaterial here
			def deliver(order)
				order.build_delivery(delivery_event_id: "evt", delivered_at: Time.current, content_hash: "hash")
			end
		end
	end
end
