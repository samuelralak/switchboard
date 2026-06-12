# frozen_string_literal: true

require "test_helper"

module Orders
	class ReconcileTest < ActiveSupport::TestCase
		test "settles a funded order from the mint checkstate" do
			order, preimage, = fund_order
			y = order.proofs.first.proof_y
			states = [ Cashu::ProofState.new(y:, state: "SPENT", witness: { preimage: }.to_json) ]

			with_checkstate(states) { Orders::Reconcile.call(order:) }

			assert_equal Orders::States::RELEASED, order.reload.current_state
		end

		test "is a no-op for an awaiting-funding order" do
			order = build_order

			assert_equal Orders::States::AWAITING_FUNDING, Orders::Reconcile.call(order:).current_state
		end

		test "is a no-op (no crash) for a funded order with no lock" do
			order = build_order
			Orders::Transition.call(order:, to: Orders::States::FUNDED) # funded directly, no lock recorded

			assert_nothing_raised { Orders::Reconcile.call(order:) }
			assert_equal Orders::States::FUNDED, order.reload.current_state
		end

		test "settles a disputed tier-2 order from the mint checkstate" do
			order = fund_tier2_order
			Orders::Transition.call(order:, to: Orders::States::DISPUTED)
			y = order.proofs.first.proof_y
			states = [ Cashu::ProofState.new(y:, state: "SPENT", witness: { signatures: [ "aa" ] }.to_json) ]

			with_checkstate(states) { Orders::Reconcile.call(order:) }

			assert_equal Orders::States::REFUNDED, order.reload.current_state
		end
	end
end
