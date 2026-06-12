# frozen_string_literal: true

require "test_helper"

class OrderDisputeTest < ActiveSupport::TestCase
	test "valid with a hex opener and a known status" do
		dispute = OrderDispute.new(order: build_order, opened_by_pubkey: SecureRandom.hex(32), status: "open")

		assert dispute.valid?
	end

	test "rejects a non-hex opener" do
		dispute = OrderDispute.new(order: build_order, opened_by_pubkey: "nope", status: "open")

		assert_not dispute.valid?
		assert dispute.errors.key?(:opened_by_pubkey)
	end

	test "rejects an unknown status" do
		dispute = OrderDispute.new(order: build_order, opened_by_pubkey: SecureRandom.hex(32), status: "bogus")

		assert_not dispute.valid?
		assert dispute.errors.key?(:status)
	end

	test "at most one dispute per order at the database" do
		order = build_order
		OrderDispute.create!(order:, opened_by_pubkey: SecureRandom.hex(32), status: "open")

		assert_raises(ActiveRecord::RecordNotUnique) do
			OrderDispute.new(order:, opened_by_pubkey: SecureRandom.hex(32), status: "open").save(validate: false)
		end
	end

	test "open? and ruled? reflect the status" do
		assert OrderDispute.new(status: "open").open?
		assert_not OrderDispute.new(status: "open").ruled?
		assert OrderDispute.new(status: "ruled_for_provider").ruled?
		assert OrderDispute.new(status: "ruled_for_consumer").ruled?
	end
end
