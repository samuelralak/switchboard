# frozen_string_literal: true

require "test_helper"

class OrderLockTest < ActiveSupport::TestCase
	test "at most one lock per order" do
		order, = fund_order

		assert_raises(ActiveRecord::RecordNotUnique) do
			OrderLock.new(order:, mint_url: order.mint_url, hashlock: SecureRandom.hex(32), locktime: 1.hour.from_now,
				lock_pubkey: "02#{SecureRandom.hex(32)}", refund_pubkey: "02#{SecureRandom.hex(32)}", amount_sats: 1)
				.save(validate: false)
		end
	end

	test "rejects a non-point lock_pubkey at the database" do
		order = build_order
		lock = OrderLock.new(order:, mint_url: order.mint_url, hashlock: SecureRandom.hex(32), locktime: 1.hour.from_now,
			lock_pubkey: "nope", refund_pubkey: "02#{SecureRandom.hex(32)}", amount_sats: 1)

		assert_raises(ActiveRecord::StatementInvalid) { lock.save(validate: false) }
	end
end
