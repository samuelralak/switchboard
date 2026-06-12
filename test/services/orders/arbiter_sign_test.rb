# frozen_string_literal: true

require "test_helper"

module Orders
	class ArbiterSignTest < ActiveSupport::TestCase
		# Two well-formed P2PK secrets whose NUT-00 points back the order's proofs, so the binding is real.
		SECRETS = [
			%q{["P2PK",{"nonce":"01","data":"02aa"}]},
			%q{["P2PK",{"nonce":"02","data":"02bb"}]}
		].freeze

		setup { ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = TEST_ARBITER_PRIVKEY }
		teardown { ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY") }

		test "signs each bound secret for the party the ruling favours (provider)" do
			order = ruled_order(winner: "provider")

			sigs = sign(order, order.provider_pubkey)

			assert_equal SECRETS.size, sigs.size
			sigs.each { |sig| assert_match(/\A[0-9a-f]{128}\z/, sig) }
		end

		test "signs for the consumer when ruled for the consumer" do
			order = ruled_order(winner: "consumer")

			sigs = sign(order, order.consumer_pubkey)

			assert_equal SECRETS.size, sigs.size
		end

		test "denies the losing party" do
			order = ruled_order(winner: "provider")

			assert_raises(AuthorizationError) { sign(order, order.consumer_pubkey) }
		end

		test "denies a stranger who is no party to the order" do
			order = ruled_order(winner: "provider")

			assert_raises(AuthorizationError) { sign(order, SecureRandom.hex(32)) }
		end

		test "refuses a secret that is not one of the order's own proofs (cross-order harvest)" do
			order = ruled_order(winner: "provider")
			foreign = %q{["P2PK",{"nonce":"99","data":"02cc"}]} # belongs to no proof of this order

			assert_raises(AuthorizationError) do
				sign(order, order.provider_pubkey, [ foreign ])
			end
		end

		test "refuses while the dispute is still open (unruled)" do
			order = disputed_order # open, never ruled

			assert_raises(AuthorizationError) { sign(order, order.provider_pubkey) }
		end

		test "refuses a funded order with no dispute" do
			order = fund_tier2_order_with_secrets(SECRETS) # funded, not disputed

			assert_raises(AuthorizationError) { sign(order, order.provider_pubkey) }
		end

		test "refuses more secrets than the order has proofs" do
			order = ruled_order(winner: "provider")
			too_many = SECRETS + [ %q{["P2PK",{"nonce":"03","data":"02dd"}]} ]

			assert_raises(AuthorizationError) do
				sign(order, order.provider_pubkey, too_many)
			end
		end

		test "refuses an empty secret list" do
			order = ruled_order(winner: "provider")

			assert_raises(AuthorizationError) { sign(order, order.provider_pubkey, []) }
		end

		private

		def sign(order, caller_pubkey, secrets = SECRETS)
			ArbiterSign.call(order:, caller_pubkey:, secrets:)
		end

		def ruled_order(winner:)
			order = disputed_order
			RuleDispute.call(order:, winner:)

			order
		end

		def disputed_order
			order = fund_tier2_order_with_secrets(SECRETS)
			Orders::Transition.call(order:, to: States::DISPUTED)
			order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status: DisputeStatuses::OPEN)

			order
		end
	end
end
