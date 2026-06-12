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

	test "a tier-2 lock is invalid without the platform arbiter" do
		lock = lock_for(build_order(tier: Orders::Tiers::TIER2_ARBITER),
			arbiter_pubkey: "02#{SecureRandom.hex(32)}", required_signatures: 2, hashlock: nil)

		assert_not lock.valid?
		assert lock.errors.key?(:arbiter_pubkey)
	end

	test "a tier-2 lock with the platform arbiter and no hashlock is valid" do
		with_arbiter_key do
			lock = lock_for(build_order(tier: Orders::Tiers::TIER2_ARBITER),
				arbiter_pubkey: platform_arbiter_pubkey, required_signatures: 2, hashlock: nil)

			assert lock.valid?
		end
	end

	test "a tier-1 lock must not carry an arbiter" do
		lock = lock_for(build_order, arbiter_pubkey: "02#{SecureRandom.hex(32)}")

		assert_not lock.valid?
		assert lock.errors.key?(:arbiter_pubkey)
	end

	test "a tier-1 lock requires a hashlock" do
		lock = lock_for(build_order, hashlock: nil)

		assert_not lock.valid?
		assert lock.errors.key?(:hashlock)
	end

	private

	def lock_for(order, **overrides)
		defaults = {
			order:, mint_url: order.mint_url, hashlock: SecureRandom.hex(32), locktime: 1.hour.from_now,
			lock_pubkey: "02#{SecureRandom.hex(32)}", refund_pubkey: "02#{SecureRandom.hex(32)}", amount_sats: 1
		}
		OrderLock.new(**defaults, **overrides)
	end
end
