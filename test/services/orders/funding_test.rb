# frozen_string_literal: true

require "test_helper"

module Orders
	class FundingTest < ActiveSupport::TestCase
		test "records the lock and proofs and moves the order to funded" do
			order = build_order(amount_sats: 1_000)

			fund(order, proofs: [ { y: point, amount: 600 }, { y: point, amount: 400 } ])

			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert order.lock.present?
			assert_equal 1_000, order.proofs.sum(:amount_sats)
		end

		test "rejects proofs that do not sum to the order amount" do
			order = build_order(amount_sats: 1_000)

			error = assert_raises(ValidationError) { fund(order, proofs: [ { y: point, amount: 999 } ]) }

			assert error.errors.key?(:proofs)
			assert_nil order.reload.lock
			assert_equal Orders::States::AWAITING_FUNDING, order.current_state
		end

		test "rejects a mint that does not match the order" do
			order = build_order

			assert_raises(ValidationError) { fund(order, mint_url: "http://localhost:3338") }
		end

		test "rejects a past locktime" do
			order = build_order

			assert_raises(ValidationError) { fund(order, locktime: 1.minute.ago) }
		end

		test "is idempotent when the same proofs are re-reported" do
			order = build_order
			proofs = [ { y: point, amount: order.amount_sats } ]
			fund(order, proofs:)

			assert_no_difference -> { OrderLock.count } do
				fund(order, proofs:)
			end
			assert_equal Orders::States::FUNDED, order.reload.current_state
		end

		test "rejects a re-report that carries different proofs" do
			order = build_order
			fund(order)

			error = assert_raises(ValidationError) { fund(order) }
			assert_includes error.errors, :proofs
		end

		test "rejects funding an order that is already settled" do
			order, = fund_order
			refund!(order)

			assert_raises(IllegalTransitionError) { fund(order) }
		end

		test "rejects a locktime that is too far in the future" do
			order = build_order

			assert_raises(ValidationError) { fund(order, locktime: (Orders::Policy.max_locktime + 1.day).from_now) }
		end

		test "rejects proofs that are already spent at the mint" do
			order = build_order(amount_sats: 1_000)
			spent = [ Cashu::ProofState.new(y: point, state: "SPENT", witness: nil) ]

			error = with_checkstate(spent) do
				assert_raises(ValidationError) do
					Orders::Funding.call(
						order:, mint_url: order.mint_url, hashlock: SecureRandom.hex(32), locktime: 1.hour.from_now,
						lock_pubkey: point, refund_pubkey: point, proofs: [ { y: point, amount: 1_000 } ]
					)
				end
			end

			assert error.errors.key?(:proofs)
			assert_nil order.reload.lock
		end

		test "funds a tier-2 order with the platform arbiter and no hashlock" do
			order = tier2_order

			with_arbiter_key { fund_tier2(order) }

			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert_equal platform_arbiter_pubkey, order.lock.arbiter_pubkey
			assert_nil order.lock.hashlock
			assert_equal 2, order.lock.required_signatures
		end

		test "rejects a tier-2 lock whose arbiter is not the platform key (anti-bypass)" do
			order = tier2_order

			error = with_arbiter_key do
				assert_raises(ValidationError) { fund_tier2(order, arbiter_pubkey: "02#{SecureRandom.hex(32)}") }
			end

			assert error.errors.key?(:arbiter_pubkey)
			assert_nil order.reload.lock
		end

		test "rejects a tier-2 lock that carries a hashlock" do
			order = tier2_order

			error = with_arbiter_key do
				assert_raises(ValidationError) { fund_tier2(order, hashlock: SecureRandom.hex(32)) }
			end

			assert error.errors.key?(:hashlock)
		end

		test "rejects a tier-2 locktime below the dispute-window minimum" do
			order = tier2_order

			error = with_arbiter_key do
				assert_raises(ValidationError) { fund_tier2(order, locktime: 1.hour.from_now) }
			end

			assert error.errors.key?(:locktime)
		end

		test "rejects tier-2 funding when no arbiter key is configured" do
			order = tier2_order

			# no with_arbiter_key -> the platform arbiter is unprovisioned
			error = assert_raises(ValidationError) { fund_tier2(order) }

			assert error.errors.key?(:tier)
		end

		private

		def refund!(order)
			states = [ Cashu::ProofState.new(y: order.proofs.first.proof_y, state: "SPENT", witness: nil) ]
			Orders::Settlement.call(order:, states:)
		end

		def point = "02#{SecureRandom.hex(32)}"

		def fund(order, **overrides)
			defaults = {
				mint_url: order.mint_url, hashlock: SecureRandom.hex(32), locktime: 1.hour.from_now,
				lock_pubkey: point, refund_pubkey: point, proofs: [ { y: point, amount: order.amount_sats } ]
			}
			with_unspent_checkstate { Orders::Funding.call(order:, **defaults.merge(overrides)) }
		end

		def tier2_order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000)

		# A Tier-2 funding report (2-of-3, no hashlock); caller wraps in with_arbiter_key when the platform
		# arbiter must be provisioned. Defaults to the matching platform arbiter key + a min-lead locktime.
		def fund_tier2(order, **overrides)
			defaults = {
				mint_url: order.mint_url, locktime: 4.days.from_now, lock_pubkey: point, refund_pubkey: point,
				arbiter_pubkey: platform_arbiter_pubkey, required_signatures: 2,
				proofs: [ { y: point, amount: order.amount_sats } ]
			}
			with_unspent_checkstate { Orders::Funding.call(order:, **defaults.merge(overrides)) }
		end
	end
end
