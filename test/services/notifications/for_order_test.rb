# frozen_string_literal: true

require "test_helper"

module Notifications
	class ForOrderTest < ActiveSupport::TestCase
		test "funded notifies the provider only" do
			order = build_order
			Notifications::ForOrder.call(order:, event: :funded)

			notification = Notification.for_recipient(order.provider_pubkey).sole
			assert_equal "order_funded", notification.notification_type
			assert_equal order.id, notification.metadata["order_id"]
			assert_equal order.amount_sats, notification.metadata["amount_sats"]
			assert_equal 0, Notification.for_recipient(order.consumer_pubkey).count
		end

		test "delivered notifies the consumer only" do
			order = build_order
			Notifications::ForOrder.call(order:, event: :delivered)

			assert_equal "order_delivered", Notification.for_recipient(order.consumer_pubkey).sole.notification_type
			assert_equal 0, Notification.for_recipient(order.provider_pubkey).count
		end

		test "released notifies the consumer (closure)" do
			order = build_order
			Notifications::ForOrder.call(order:, event: :released)

			assert_equal "order_released", Notification.for_recipient(order.consumer_pubkey).sole.notification_type
		end

		test "release_authorized prompts the provider to redeem" do
			order = build_order
			Notifications::ForOrder.call(order:, event: :release_authorized)

			assert_equal "order_release_authorized", Notification.for_recipient(order.provider_pubkey).sole.notification_type
			assert_equal 0, Notification.for_recipient(order.consumer_pubkey).count
		end

		test "refunded and expired notify both parties" do
			order = build_order
			Notifications::ForOrder.call(order:, event: :refunded)

			assert_equal "order_refunded", Notification.for_recipient(order.consumer_pubkey).sole.notification_type
			assert_equal "order_refunded", Notification.for_recipient(order.provider_pubkey).sole.notification_type
		end

		test "a placed request claim alerts the requester (consumer)" do
			order = build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM)
			Notifications::ForOrder.call(order:, event: :placed)

			assert_equal "request_claimed", Notification.for_recipient(order.consumer_pubkey).sole.notification_type
			assert_equal 0, Notification.for_recipient(order.provider_pubkey).count
		end

		test "a placed catalog order is silent" do
			order = build_order(entry_point: Orders::EntryPoints::CATALOG_ORDER)

			assert_no_difference("Notification.count") { Notifications::ForOrder.call(order:, event: :placed) }
		end

		test "an event with no recipients is a no-op" do
			order = build_order

			assert_no_difference("Notification.count") { Notifications::ForOrder.call(order:, event: :awaiting_funding) }
		end
	end
end
