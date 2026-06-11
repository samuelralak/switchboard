# frozen_string_literal: true

require "test_helper"

# Exercises the REAL after_commit notification wiring on the order lifecycle. Non-transactional so the order
# services' txn.after_commit hooks actually fire (they do not in transactional tests); rows are cleaned up in
# teardown. Asserts on deltas so any baseline is irrelevant. The recipient/type mapping itself is unit-covered
# by Notifications::ForOrderTest; this proves the hooks fire once, to the right party, and not on re-runs.
class OrderNotificationsTest < ActiveSupport::TestCase
	self.use_transactional_tests = false

	teardown do
		Notification.delete_all
		Order.destroy_all # cascades transitions/effects/proofs/lock/delivery/release
	end

	test "funding an order notifies the provider" do
		order = build_order

		assert_difference -> { Notification.for_recipient(order.provider_pubkey).count }, 1 do
			Orders::Transition.call(order:, to: Orders::States::FUNDED)
		end
		assert_equal "order_funded", Notification.for_recipient(order.provider_pubkey).recent.first.notification_type
	end

	test "marking delivered notifies the consumer once, even on a re-delivery" do
		order = funded

		assert_difference -> { Notification.for_recipient(order.consumer_pubkey).count }, 1 do
			Orders::MarkDelivered.call(order:, delivery_event_id: hex, delivered_at: Time.current.to_i, content_hash: hex)
		end
		assert_no_difference -> { Notification.for_recipient(order.consumer_pubkey).count } do
			Orders::MarkDelivered.call(order:, delivery_event_id: hex, delivered_at: Time.current.to_i, content_hash: hex)
		end
	end

	test "a release reveal prompts the provider once, even on a re-reveal" do
		order = funded

		assert_difference -> { Notification.for_recipient(order.provider_pubkey).count }, 1 do
			Orders::MarkReleased.call(order:, reveal_event_id: hex, released_at: Time.current.to_i)
		end
		notification = Notification.for_recipient(order.provider_pubkey).recent.first
		assert_equal "order_release_authorized", notification.notification_type
		assert_no_difference -> { Notification.for_recipient(order.provider_pubkey).count } do
			Orders::MarkReleased.call(order:, reveal_event_id: hex, released_at: Time.current.to_i)
		end
	end

	test "a request-claim order notifies the requester on creation, but an idempotent re-create does not" do
		args = claim_args
		order = nil

		assert_difference -> { Notification.count }, 1 do
			order = Orders::Create.call(**args)
		end
		assert_equal "request_claimed", Notification.for_recipient(order.consumer_pubkey).recent.first.notification_type
		assert_no_difference -> { Notification.count } do
			Orders::Create.call(**args) # same dedupe_key + identity -> returns the existing order, no new notification
		end
	end

	private

	def funded
		order = build_order
		order.state_machine.transition_to!(Orders::States::FUNDED) # raw machine: no Transition-service notification
		order
	end

	def claim_args
		{
			entry_point: Orders::EntryPoints::REQUEST_CLAIM, consumer_pubkey: SecureRandom.hex(32),
			provider_pubkey: SecureRandom.hex(32), listing_coordinate: "30402:#{SecureRandom.hex(32)}:req",
			amount_sats: 1_000, mint_url: "http://127.0.0.1:3338", dedupe_key: SecureRandom.hex(16),
			funding_deadline_at: 1.hour.from_now
		}
	end

	def hex = SecureRandom.hex(32)
end
