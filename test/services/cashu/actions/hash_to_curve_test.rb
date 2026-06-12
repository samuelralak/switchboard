# frozen_string_literal: true

require "test_helper"

module Cashu
	module Actions
		class HashToCurveTest < ActiveSupport::TestCase
			# Official NUT-00 hash_to_curve test vectors (input is the 32 raw bytes, not a UTF-8 string). Pinning
			# these guarantees Rails derives the same Y the mint does, so the secret->proof binding is sound.
			VECTORS = {
				"00" * 32 => "024cce997d3b518f739663b757deaec95bcd9473c30a14ac2fd04023a739d1a725",
				"#{'00' * 31}01" => "022e7158e11c9506f1aa4248bf531298daa7febd6194f003edcd9b93ade6253acf",
				"#{'00' * 31}02" => "026cdbe15362df59cd1dd3c9c11de8aedac2106eca69236ecd9fbe117af897be4f"
			}.freeze

			test "matches the official NUT-00 test vectors" do
				VECTORS.each do |hex, expected|
					assert_equal expected, HashToCurve.call(secret: [ hex ].pack("H*")), "vector #{hex}"
				end
			end

			test "returns a compressed (even-y, 02-prefixed) secp256k1 point" do
				y = HashToCurve.call(secret: %q{["P2PK",{"nonce":"a","data":"02ab"}]})

				assert_match Cashu::POINT, y
				assert y.start_with?("02"), "NUT-00 forces the even-y point"
			end

			test "is deterministic for a given secret" do
				assert_equal HashToCurve.call(secret: "the-secret"), HashToCurve.call(secret: "the-secret")
			end

			test "distinct secrets map to distinct points" do
				assert_not_equal HashToCurve.call(secret: "a"), HashToCurve.call(secret: "b")
			end
		end
	end
end
