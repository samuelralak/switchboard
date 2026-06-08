# frozen_string_literal: true

require "test_helper"

module Cashu
	# Orchestration: the empty short-circuit and the allowlist guard are exercised with no mint; the protocol
	# round-trip runs against a local nutshell mint when one is up. Body parsing is covered by IndexStatesTest;
	# SPENT/witness detection end-to-end by the cashu system test.
	class CheckstateTest < ActiveSupport::TestCase
		MINT = "http://127.0.0.1:3338"

		test "returns an empty result for no Ys, without a request" do
			assert_empty Cashu::Checkstate.call(mint_url: MINT, ys: [])
		end

		test "refuses a mint that is not allowlisted, before any request" do
			assert_raises(Cashu::MintError) { Cashu::Checkstate.call(mint_url: "https://evil.example", ys: [ point ]) }
		end

		test "returns UNSPENT states for unknown proof Ys, in request order" do
			skip("no Cashu mint at #{MINT}") unless mint_up?
			ys = [ point, point ]

			states = Cashu::Checkstate.call(mint_url: MINT, ys:)

			assert_equal ys, states.map(&:y)
			assert states.all?(&:unspent?)
		end

		private

		# A real compressed point: a BIP-340 x-only pubkey is a valid x with even y, so "02" + x is on the curve.
		def point = "02#{Nostr::Keygen.new.generate_key_pair.public_key}"

		def mint_up?
			require "net/http"
			Net::HTTP.start("127.0.0.1", 3338, open_timeout: 2, read_timeout: 2) { |h| h.get("/v1/info").is_a?(Net::HTTPSuccess) }
		rescue StandardError
			false
		end
	end
end
