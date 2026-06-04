# frozen_string_literal: true

require "test_helper"

module Operational
	class SignerTest < ActiveSupport::TestCase
		def setup
			@keypair = Nostr::Keygen.new.generate_key_pair
			@signer = Operational::Signer.new(private_key: @keypair.private_key.to_s)
		end

		test "exposes the x-only pubkey without a public reader for the key" do
			assert_equal @keypair.public_key.to_s, @signer.pubkey
			assert_not @signer.respond_to?(:private_key)
		end

		test "signs an event that passes Events::Verify" do
			event = @signer.sign(kind: Events::Kinds::AUTH, tags: [ [ "relay", "wss://r.example" ], [ "challenge", "x" ] ])

			assert_equal @signer.pubkey, event["pubkey"]
			assert_equal Events::Kinds::AUTH, event["kind"]
			assert_nothing_raised { Events::Verify.call(event_data: event) }
		end

		test "fails loudly when no R_op key is set in ENV" do
			original = ENV.delete(Operational::Signer::ENV_VAR)
			assert_raises(KeyError) { Operational::Signer.env_key }
		ensure
			ENV[Operational::Signer::ENV_VAR] = original
		end

		test "reports the R_op key as unconfigured when ENV is empty" do
			original = ENV.delete(Operational::Signer::ENV_VAR)
			assert_not Operational::Signer.configured?
		ensure
			ENV[Operational::Signer::ENV_VAR] = original
		end

		test "reports configured when the R_op key is present in ENV" do
			original = ENV.fetch(Operational::Signer::ENV_VAR, nil)
			ENV[Operational::Signer::ENV_VAR] = "a" * 64
			assert Operational::Signer.configured?
		ensure
			ENV[Operational::Signer::ENV_VAR] = original
		end
	end
end
