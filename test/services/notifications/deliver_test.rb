# frozen_string_literal: true

require "test_helper"

module Notifications
	class DeliverTest < ActiveSupport::TestCase
		test "records a recipient-addressed notification" do
			notification = Notifications::Deliver.call(
				recipient_pubkey: "a" * 64, notification_type: "order_funded",
				metadata: { "order_id" => "abc", "amount_sats" => 5_000 }
			)

			assert notification.persisted?
			assert_equal "a" * 64, notification.recipient_pubkey
			assert_equal "order_funded", notification.notification_type
			assert_equal({ "order_id" => "abc", "amount_sats" => 5_000 }, notification.metadata)
			assert_nil notification.seen_at
			assert_nil notification.read_at
		end

		test "defaults metadata to an empty hash" do
			notification = Notifications::Deliver.call(recipient_pubkey: "a" * 64, notification_type: "order_delivered")

			assert_equal({}, notification.metadata)
		end

		test "raises on an invalid recipient pubkey" do
			assert_raises(ActiveRecord::RecordInvalid) do
				Notifications::Deliver.call(recipient_pubkey: "nope", notification_type: "x")
			end
		end
	end
end
