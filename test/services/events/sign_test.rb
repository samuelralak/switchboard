# frozen_string_literal: true

require "test_helper"

module Events
	class SignTest < ActiveSupport::TestCase
		# NIP-59 published example author keypair.
		VECTOR_PRIV = "0beebd062ec8735f4243466049d7747ef5d6594ee838de147f8aab842b15e273"
		VECTOR_PUB  = "611df01bfcf85c26ae65453b772d8f1dfd25c264621c0277e1fc1518686faef9"
		ODD_Y_PRIV  = "0000000000000000000000000000000000000000000000000000000000000006" # d=6: pubkey Y is odd

		test "derives the BIP-340 x-only pubkey matching the NIP-59 vector" do
			signed = Events::Sign.call(private_key: VECTOR_PRIV, kind: 1, content: "x")
			assert_equal VECTOR_PUB, signed["pubkey"]
		end

		# Signing with our own canonical id (JSON.generate) must round-trip through Verify
		# even for &<> content, which is exactly where the gem's JSON.dump path would drift.
		test "produces an event that passes Events::Verify, including & < > content" do
			signed = Events::Sign.call(private_key: VECTOR_PRIV, kind: 1, content: "hello & <world>")
			assert_nothing_raised { Events::Verify.call(event_data: signed) }
		end

		test "computes the id with the shared canonical serializer" do
			signed = Events::Sign.call(private_key: VECTOR_PRIV, kind: 1, content: "y")
			assert_equal Events::Actions::ComputeCanonicalId.call(event: signed), signed["id"]
		end

		# A private key whose pubkey has odd Y (d = 6) must still sign -> verify: the schnorr
		# library negates the scalar so the signature validates against the even-Y x-only pubkey.
		test "signs and verifies a key whose pubkey has odd Y" do
			signed = Events::Sign.call(private_key: ODD_Y_PRIV, kind: 1, content: "x")
			assert_nothing_raised { Events::Verify.call(event_data: signed) }
		end
	end
end
