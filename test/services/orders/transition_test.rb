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

		private

		def funded_order
			build_order.tap { |order| Orders::Transition.call(order:, to: Orders::States::FUNDED) }
		end
	end
end
