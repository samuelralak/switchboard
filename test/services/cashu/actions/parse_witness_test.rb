# frozen_string_literal: true

require "test_helper"

module Cashu
	module Actions
		class ParseWitnessTest < ActiveSupport::TestCase
			test "parses a JSON-string witness into preimage + signatures" do
				result = ParseWitness.call(witness: { preimage: "ab" * 32, signatures: [ "sig" ] }.to_json)

				assert_equal "ab" * 32, result[:preimage]
				assert_equal [ "sig" ], result[:signatures]
			end

			test "accepts an already-decoded object witness" do
				result = ParseWitness.call(witness: { "preimage" => "cd" * 32 })

				assert_equal "cd" * 32, result[:preimage]
				assert_equal [], result[:signatures]
			end

			test "a blank witness has no preimage" do
				assert_nil ParseWitness.call(witness: nil)[:preimage]
				assert_nil ParseWitness.call(witness: "")[:preimage]
			end

			test "a non-object witness yields no preimage and never raises" do
				[ '"just a string"', "[1,2]", "42" ].each do |witness|
					assert_nil ParseWitness.call(witness:)[:preimage], "#{witness.inspect} should yield a nil preimage"
				end
			end

			test "an unparseable witness yields no preimage" do
				assert_nil ParseWitness.call(witness: "{not json")[:preimage]
			end
		end
	end
end
