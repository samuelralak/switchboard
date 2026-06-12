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
	end
end
