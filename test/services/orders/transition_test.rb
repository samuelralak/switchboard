# frozen_string_literal: true

require "test_helper"

module Orders
	class TransitionTest < ActiveSupport::TestCase
		test "advances state and appends a ledger row" do
			order = build_order

			Orders::Transition.call(order:, to: Orders::States::FUNDED)

			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert_equal Orders::States::FUNDED, order.state_machine.current_state(force_reload: true)
			assert_equal [ "funded" ], order.order_transitions.order(:sort_key).pluck(:to_state)
		end

		test "rejects an illegal transition and leaves state untouched" do
			order = build_order

			assert_raises(IllegalTransitionError) { Orders::Transition.call(order:, to: Orders::States::RELEASED) }
			assert_equal Orders::States::AWAITING_FUNDING, order.reload.current_state
			assert_empty order.order_transitions
		end

		test "is idempotent when already in the target state" do
			order = build_order
			Orders::Transition.call(order:, to: Orders::States::FUNDED)

			assert_no_difference -> { order.order_transitions.count } do
				Orders::Transition.call(order:, to: Orders::States::FUNDED)
			end
		end

		test "records a settlement effect on release" do
			order = funded_order

			Orders::Transition.call(order:, to: Orders::States::RELEASED)

			assert_equal Orders::States::RELEASED, order.reload.current_state
			assert_equal [ Orders::States::RELEASED ], order.effects.pluck(:kind)
		end

		test "records a settlement effect on refund" do
			order = funded_order

			Orders::Transition.call(order:, to: Orders::States::REFUNDED)

			assert_equal [ Orders::States::REFUNDED ], order.effects.pluck(:kind)
		end

		test "a released order cannot be refunded" do
			order = funded_order
			Orders::Transition.call(order:, to: Orders::States::RELEASED)

			assert_raises(IllegalTransitionError) { Orders::Transition.call(order:, to: Orders::States::REFUNDED) }
			assert_equal 1, order.effects.count
		end

		test "expires an unfunded order without an effect" do
			order = build_order

			Orders::Transition.call(order:, to: Orders::States::EXPIRED)

			assert_equal Orders::States::EXPIRED, order.reload.current_state
			assert_empty order.effects
		end

		test "sort_key increments per transition" do
			order = funded_order
			Orders::Transition.call(order:, to: Orders::States::RELEASED)

			assert_equal [ 10, 20 ], order.order_transitions.order(:sort_key).pluck(:sort_key)
		end

		test "a funded tier-2 order can move to disputed without settling" do
			order = funded_tier2

			Orders::Transition.call(order:, to: Orders::States::DISPUTED)

			assert_equal Orders::States::DISPUTED, order.reload.current_state
			assert_empty order.effects # a dispute is not yet a settlement
		end

		test "a tier-1 order cannot be disputed (it has no mediator)" do
			order = funded_order

			assert_raises(IllegalTransitionError) { Orders::Transition.call(order:, to: Orders::States::DISPUTED) }
			assert_equal Orders::States::FUNDED, order.reload.current_state
		end

		test "a disputed order releases with one settlement effect" do
			order = disputed_order

			Orders::Transition.call(order:, to: Orders::States::RELEASED)

			assert_equal Orders::States::RELEASED, order.reload.current_state
			assert_equal [ Orders::States::RELEASED ], order.effects.pluck(:kind)
		end

		test "a disputed order refunds with one settlement effect" do
			order = disputed_order

			Orders::Transition.call(order:, to: Orders::States::REFUNDED)

			assert_equal [ Orders::States::REFUNDED ], order.effects.pluck(:kind)
		end

		test "a disputed order cannot return to funded" do
			order = disputed_order

			assert_raises(IllegalTransitionError) { Orders::Transition.call(order:, to: Orders::States::FUNDED) }
			assert_equal Orders::States::DISPUTED, order.reload.current_state
		end

		private

		def funded_order
			build_order.tap { |order| Orders::Transition.call(order:, to: Orders::States::FUNDED) }
		end

		# A funded Tier-2 order (only Tier-2 may be disputed). No lock is needed for these state-machine tests.
		def funded_tier2
			order = build_order(tier: Orders::Tiers::TIER2_ARBITER)
			Orders::Transition.call(order:, to: Orders::States::FUNDED)
			order
		end

		def disputed_order
			funded_tier2.tap { |order| Orders::Transition.call(order:, to: Orders::States::DISPUTED) }
		end
	end
end
