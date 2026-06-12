# frozen_string_literal: true

require "test_helper"

module Orders
	class RuleDisputeTest < ActiveSupport::TestCase
		test "rules for the provider and records the outcome" do
			order = disputed_order

			RuleDispute.call(order:, winner: "provider")

			dispute = order.dispute.reload
			assert dispute.ruled_for_provider?
			assert_not_nil dispute.ruled_at
		end

		test "rules for the consumer" do
			order = disputed_order

			RuleDispute.call(order:, winner: "consumer")

			assert order.dispute.reload.ruled_for_consumer?
		end

		test "leaves the order disputed -- the on-mint spend settles it later" do
			order = disputed_order

			RuleDispute.call(order:, winner: "provider")

			assert_equal States::DISPUTED, order.reload.current_state
		end

		test "rejects an unknown winner and leaves the dispute open" do
			order = disputed_order

			assert_raises(ValidationError) { RuleDispute.call(order:, winner: "nobody") }
			assert order.dispute.reload.open?
		end

		test "is idempotent when re-ruled the same way" do
			order = disputed_order
			RuleDispute.call(order:, winner: "provider")
			first_ruled_at = order.dispute.reload.ruled_at

			assert_nothing_raised { RuleDispute.call(order:, winner: "provider") }
			assert_equal first_ruled_at, order.dispute.reload.ruled_at
		end

		test "refuses to flip a ruling to the other party" do
			order = disputed_order
			RuleDispute.call(order:, winner: "provider")

			assert_raises(IllegalTransitionError) { RuleDispute.call(order:, winner: "consumer") }
			assert order.dispute.reload.ruled_for_provider?
		end

		test "rejects ruling an order with no dispute" do
			order = fund_tier2_order # funded, never disputed

			assert_raises(IllegalTransitionError) { RuleDispute.call(order:, winner: "provider") }
		end

		private

		def disputed_order
			order = fund_tier2_order
			Orders::Transition.call(order:, to: States::DISPUTED)
			order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status: DisputeStatuses::OPEN)

			order
		end
	end
end
