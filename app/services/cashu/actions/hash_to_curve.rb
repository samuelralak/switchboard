# frozen_string_literal: true

require "digest"
require "ecdsa_ext"

module Cashu
	module Actions
		# NUT-00 hash_to_curve: deterministically map a proof secret to its point Y on secp256k1 -- the proof's
		# on-mint identity. With msg_hash = SHA256(DOMAIN_SEPARATOR || secret), Y is 02 || SHA256(msg_hash ||
		# counter) for the first uint32 (little-endian) counter whose 32-byte candidate is a valid curve
		# x-coordinate (about half are, so it resolves in a few rounds). Matches cashu-ts hashToCurve
		# (cross-language tested), so Rails can bind a submitted secret to a recorded proof Y -- the arbiter
		# signs only secrets belonging to the ruled order -- without ever persisting the secret.
		class HashToCurve < BaseService
			DOMAIN_SEPARATOR = "Secp256k1_HashToCurve_Cashu_".b
			MAX_COUNTER = 2**32 # NUT-00 bound; never approached (a miss streak this long is ~2^-32 likely)

			option :secret, type: Types::Strict::String

			def call
				msg_hash = Digest::SHA256.digest(DOMAIN_SEPARATOR + secret.b)

				MAX_COUNTER.times do |counter|
					candidate = "\x02".b + Digest::SHA256.digest(msg_hash + [ counter ].pack("V"))
					return candidate.unpack1("H*") if on_curve?(candidate)
				end

				raise MintError, "no curve point for the secret" # unreachable for any real secret
			end

			private

			# A compressed candidate decodes iff its x lies on secp256k1; the 02 prefix forces the even-y point,
			# so the returned Y matches cashu-ts byte for byte.
			def on_curve?(candidate)
				ECDSA::Format::PointOctetString.decode(candidate, ECDSA::Group::Secp256k1)
				true
			rescue ECDSA::Format::DecodeError
				false
			end
		end
	end
end
