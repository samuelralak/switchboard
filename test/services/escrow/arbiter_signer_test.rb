# frozen_string_literal: true

require "test_helper"

module Escrow
	class ArbiterSignerTest < ActiveSupport::TestCase
		test "derives a compressed secp256k1 point from the private key" do
			pubkey = ArbiterSigner.new(private_key: "11" * 32).pubkey

			assert_match(/\A0[23][0-9a-f]{64}\z/, pubkey)
		end

		test "is deterministic for a given key" do
			key = SecureRandom.hex(32)

			assert_equal ArbiterSigner.new(private_key: key).pubkey, ArbiterSigner.new(private_key: key).pubkey
		end

		test "configured? requires a well-formed 64-hex key in ENV" do
			with_arbiter_key { assert ArbiterSigner.configured? }

			ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = "not-hex"
			assert_not ArbiterSigner.configured?
		ensure
			ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY")
		end

		test "the class pubkey is nil when unconfigured" do
			ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY")

			assert_nil ArbiterSigner.pubkey
		end

		test "sign produces a 128-hex BIP-340 signature over the secret" do
			sig = ArbiterSigner.new(private_key: "33" * 32).sign(%q{["P2PK",{"nonce":"a","data":"02ab"}]})

			assert_match(/\A[0-9a-f]{128}\z/, sig)
		end

		test "signing is deterministic for a given key and secret" do
			signer = ArbiterSigner.new(private_key: "33" * 32)

			assert_equal signer.sign("the-secret"), signer.sign("the-secret")
		end
	end
end
