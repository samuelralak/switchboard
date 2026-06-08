# frozen_string_literal: true

require "test_helper"

class OrderProofTest < ActiveSupport::TestCase
	test "proof_y is globally unique at the database" do
		y = "02#{SecureRandom.hex(32)}"
		build_order.proofs.create!(proof_y: y, amount_sats: 1)
		dup = OrderProof.new(order: build_order, proof_y: y, amount_sats: 1)

		assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
	end

	test "rejects a non-point proof_y at the database" do
		proof = OrderProof.new(order: build_order, proof_y: "nope", amount_sats: 1)

		assert_raises(ActiveRecord::StatementInvalid) { proof.save(validate: false) }
	end
end
