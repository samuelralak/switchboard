# frozen_string_literal: true

require "test_helper"

module Cashu
	module Actions
		# Parsing/validation of a NUT-07 checkstate body, exercised directly (no mint). SPENT/witness detection
		# is covered end-to-end by the cashu system test.
		class IndexStatesTest < ActiveSupport::TestCase
			test "rejects a non-array states field" do
				assert_raises(Cashu::MintError) { index('{"states": null}') }
				assert_raises(Cashu::MintError) { index('{"states": "nope"}') }
			end

			test "rejects an unparseable body" do
				assert_raises(Cashu::MintError) { index("not json") }
			end

			test "rejects duplicate Y values (a last-wins duplicate could flip a state)" do
				body = { states: [ { Y: "02ab", state: "UNSPENT" }, { Y: "02ab", state: "SPENT" } ] }.to_json

				assert_raises(Cashu::MintError) { index(body) }
			end

			test "normalizes Y case so an uppercase response still matches" do
				y = point
				body = { states: [ { Y: y.upcase, state: "SPENT", witness: nil } ] }.to_json

				assert_equal "SPENT", index(body)[y]["state"]
			end

			private

			def index(body) = Cashu::Actions::IndexStates.call(body:)

			# A real compressed point: a BIP-340 x-only pubkey is a valid x with even y, so "02" + x is on the curve.
			def point = "02#{Nostr::Keygen.new.generate_key_pair.public_key}"
		end
	end
end
