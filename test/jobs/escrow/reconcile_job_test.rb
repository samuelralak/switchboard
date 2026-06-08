# frozen_string_literal: true

require "test_helper"

module Escrow
	class ReconcileJobTest < ActiveJob::TestCase
		test "reconciles a funded order to settlement" do
			order, preimage, = fund_order
			y = order.proofs.first.proof_y
			states = [ Cashu::ProofState.new(y:, state: "SPENT", witness: { preimage: }.to_json) ]

			with_checkstate(states) { Escrow::ReconcileJob.perform_now(order.id) }

			assert_equal Orders::States::RELEASED, order.reload.current_state
		end

		test "is a no-op for a missing order" do
			assert_nothing_raised { Escrow::ReconcileJob.perform_now(SecureRandom.uuid) }
		end
	end
end
