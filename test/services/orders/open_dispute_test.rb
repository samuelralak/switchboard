# frozen_string_literal: true

require "test_helper"

module Orders
	class OpenDisputeTest < ActiveSupport::TestCase
		test "the consumer opens a dispute, moving the order to disputed" do
			order = fund_tier2_order

			Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey, reason: "no delivery")

			assert_equal Orders::States::DISPUTED, order.reload.current_state
			assert_equal Orders::DisputeStatuses::OPEN, order.dispute.status
			assert_equal order.consumer_pubkey, order.dispute.opened_by_pubkey
		end

		test "the provider can open a dispute" do
			order = fund_tier2_order

			Orders::OpenDispute.call(order:, opened_by_pubkey: order.provider_pubkey)

			assert_equal Orders::States::DISPUTED, order.reload.current_state
		end

		test "rejects a non-party opener" do
			order = fund_tier2_order

			assert_raises(ValidationError) { Orders::OpenDispute.call(order:, opened_by_pubkey: SecureRandom.hex(32)) }
			assert_equal Orders::States::FUNDED, order.reload.current_state
		end

		test "rejects a dispute once a release is authorized (no clawing back an authorized release)" do
			order = fund_tier2_order
			order.create_release!(reveal_event_id: SecureRandom.hex(32), released_at: Time.current)

			assert_raises(IllegalTransitionError) { Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey) }
			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert_nil order.dispute
		end

		test "rejects a tier-1 order" do
			order, = fund_order

			assert_raises(ValidationError) { Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey) }
			assert_equal Orders::States::FUNDED, order.reload.current_state
		end

		test "rejects a non-funded order" do
			order = build_order(tier: Orders::Tiers::TIER2_ARBITER)

			assert_raises(IllegalTransitionError) do
				Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey)
			end
		end

		test "is idempotent on a re-open" do
			order = fund_tier2_order
			Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey)

			assert_no_difference -> { OrderDispute.count } do
				Orders::OpenDispute.call(order:, opened_by_pubkey: order.provider_pubkey)
			end
			assert_equal Orders::States::DISPUTED, order.reload.current_state
		end
	end
end
