# frozen_string_literal: true

require "test_helper"

module Orders
	class SettlementTest < ActiveSupport::TestCase
		test "releases when a spent witness reveals the lock preimage" do
			order, preimage, = fund_order
			states = [ spent(order, witness: { preimage: }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::RELEASED, order.reload.current_state
			assert_equal [ Orders::States::RELEASED ], order.effects.pluck(:kind)
		end

		test "refunds when a spent witness carries no matching preimage" do
			order, = fund_order
			states = [ spent(order, witness: { signatures: [ "ab" ] }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::REFUNDED, order.reload.current_state
			assert_equal [ Orders::States::REFUNDED ], order.effects.pluck(:kind)
		end

		test "refunds when a spent proof has no witness" do
			order, = fund_order

			Orders::Settlement.call(order:, states: [ spent(order, witness: nil) ])

			assert_equal Orders::States::REFUNDED, order.reload.current_state
		end

		test "a wrong preimage does not release" do
			order, = fund_order
			states = [ spent(order, witness: { preimage: SecureRandom.hex(32) }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::REFUNDED, order.reload.current_state
		end

		test "is a no-op while all proofs are unspent" do
			order, = fund_order
			y = order.proofs.first.proof_y

			Orders::Settlement.call(order:, states: [ proof_state(y, "UNSPENT", nil) ])

			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert_empty order.effects
		end

		test "is a no-op for a non-funded order" do
			order = build_order

			Orders::Settlement.call(order:, states: [ proof_state("02#{SecureRandom.hex(32)}", "SPENT", nil) ])

			assert_equal Orders::States::AWAITING_FUNDING, order.reload.current_state
		end

		test "waits while only some proofs are spent (settlement is atomic)" do
			order = build_order(amount_sats: 1_000)
			preimage = SecureRandom.hex(32)
			hashlock = ::Digest::SHA256.hexdigest([ preimage ].pack("H*"))
			ys = [ "02#{SecureRandom.hex(32)}", "02#{SecureRandom.hex(32)}" ]
			with_unspent_checkstate do
				Orders::Funding.call(
					order:, mint_url: order.mint_url, hashlock:, locktime: 1.hour.from_now,
					lock_pubkey: "02#{SecureRandom.hex(32)}", refund_pubkey: "02#{SecureRandom.hex(32)}",
					proofs: [ { y: ys[0], amount: 600 }, { y: ys[1], amount: 400 } ]
				)
			end
			states = [ proof_state(ys[0], "SPENT", { preimage: }.to_json), proof_state(ys[1], "UNSPENT", nil) ]

			Orders::Settlement.call(order: order.reload, states:)

			assert_equal Orders::States::FUNDED, order.reload.current_state
			assert_empty order.effects
		end

		test "tier-2 releases on a two-of-three spend once the consumer has asserted release" do
			order = fund_tier2_order
			order.create_release!(reveal_event_id: SecureRandom.hex(32), released_at: Time.current)
			states = [ spent(order, witness: { signatures: %w[aa bb] }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::RELEASED, order.reload.current_state
			assert_equal [ Orders::States::RELEASED ], order.effects.pluck(:kind)
		end

		test "tier-2 does NOT release on a padded two-sig spend without a release assertion" do
			order = fund_tier2_order # no release on record
			states = [ spent(order, witness: { signatures: %w[aa bb] }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::REFUNDED, order.reload.current_state # a mint cannot fake the consumer's release
		end

		test "tier-2 refunds on a single-signature refund-path spend" do
			order = fund_tier2_order

			Orders::Settlement.call(order:, states: [ spent(order, witness: { signatures: [ "aa" ] }.to_json) ])

			assert_equal Orders::States::REFUNDED, order.reload.current_state
		end

		test "tier-2 refunds conservatively on an empty witness" do
			order = fund_tier2_order

			Orders::Settlement.call(order:, states: [ spent(order, witness: nil) ])

			assert_equal Orders::States::REFUNDED, order.reload.current_state
		end

		test "tier-2 ignores a stray preimage (only the signature count decides direction)" do
			order = fund_tier2_order
			states = [ spent(order, witness: { preimage: SecureRandom.hex(32), signatures: [ "aa" ] }.to_json) ]

			Orders::Settlement.call(order:, states:)

			assert_equal Orders::States::REFUNDED, order.reload.current_state # one signature => refund; preimage irrelevant
		end

		test "a disputed tier-2 order releases on a 2-sig spend once the consumer has asserted release" do
			order = fund_tier2_order
			Orders::Transition.call(order:, to: Orders::States::DISPUTED)
			order.create_release!(reveal_event_id: SecureRandom.hex(32), released_at: Time.current)

			Orders::Settlement.call(order:, states: [ spent(order, witness: { signatures: %w[aa bb] }.to_json) ])

			assert_equal Orders::States::RELEASED, order.reload.current_state
		end

		test "a concurrent terminalization makes settlement a clean no-op rather than raising" do
			order, preimage, = fund_order
			# a competing settlement won the lock first, so this order's transition is now illegal
			Orders::Transition.singleton_class.define_method(:call) { |**| raise IllegalTransitionError, "concurrent" }

			begin
				assert_nothing_raised do
					Orders::Settlement.call(order:, states: [ spent(order, witness: { preimage: }.to_json) ])
				end
			ensure
				Orders::Transition.singleton_class.send(:remove_method, :call)
			end
		end

		private

		def spent(order, witness:)
			proof_state(order.proofs.first.proof_y, "SPENT", witness)
		end

		def proof_state(proof_y, state, witness)
			Cashu::ProofState.new(y: proof_y, state:, witness:)
		end
	end
end
