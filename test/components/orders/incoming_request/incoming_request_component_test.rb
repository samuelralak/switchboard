# frozen_string_literal: true

require "test_helper"

module Orders
	module IncomingRequest
		class IncomingRequestComponentTest < ViewComponent::TestCase
			def viewer(pubkey)
				User.new(pubkey:)
			end

			test "renders the client-decrypt panel for the provider on an active catalog order" do
				order = build_order(entry_point: Orders::EntryPoints::CATALOG_ORDER)

				render_inline(IncomingRequestComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_selector "[data-controller='messages'][data-messages-own-value='#{order.provider_pubkey}']"
				assert_selector "[data-messages-consumer-value='#{order.consumer_pubkey}']"
				assert_selector "[data-messages-target='request']"
			end

			test "does not render for the consumer (they have the send form, not the decrypt view)" do
				order = build_order(entry_point: Orders::EntryPoints::CATALOG_ORDER)

				render_inline(IncomingRequestComponent.new(order:, viewer: viewer(order.consumer_pubkey)))

				assert_no_selector "[data-controller='messages']"
			end

			test "does not render for a claimed request (already public on relays)" do
				order = build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM)

				render_inline(IncomingRequestComponent.new(order:, viewer: viewer(order.provider_pubkey)))

				assert_no_selector "[data-controller='messages']"
			end
		end
	end
end
