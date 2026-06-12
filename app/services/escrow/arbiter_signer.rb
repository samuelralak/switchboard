# frozen_string_literal: true

require "ecdsa_ext"

module Escrow
	# The platform's Tier-2 arbiter key: a DEDICATED secp256k1 Cashu key (not R_op, not a Nostr key) that the
	# platform co-signs disputed 2-of-3 order locks with. Its PRIVATE key signs proof secrets at ruling time
	# only (Tier-2 Slice 4); it is 1-of-3 with n_sigs=2 so it is never sufficient alone, never a payee, and
	# never in the refund set, so the platform stays a signer, not a custodian (non-custody, brief sec 6.3).
	# The hex key is read from ENV and touched ONLY here; its reader is private so the key cannot leak. The
	# PUBLIC key (compressed SEC1 point) is advertised to browsers so a consumer locks to it, and the funding
	# contract rejects any other arbiter key. See docs/tier2-arbiter-escrow.md.
	class ArbiterSigner
		extend Dry::Initializer

		ENV_VAR = "ESCROW_TIER2_ARBITER_PRIVKEY"
		PRIVKEY_FORMAT = /\A[0-9a-f]{64}\z/i

		option :private_key, type: Types::Strict::String, reader: :private, default: -> { self.class.env_key }

		# True when the arbiter key is provisioned. Gates whether Tier-2 is offered/fundable at all.
		def self.configured?
			ENV.fetch(ENV_VAR, nil).to_s.match?(PRIVKEY_FORMAT)
		end

		# The advertised arbiter pubkey, or nil when unconfigured (so callers gate cleanly).
		def self.pubkey
			configured? ? new.pubkey : nil
		end

		def self.env_key
			key = ENV.fetch(ENV_VAR, nil).to_s
			raise(KeyError, "arbiter key missing or malformed: set #{ENV_VAR} (64-hex)") unless key.match?(PRIVKEY_FORMAT)

			key.downcase
		end

		# The compressed (SEC1, 02/03-prefixed, 66-hex) secp256k1 point the consumer locks to. Matches cashu-ts
		# getPubKeyFromPrivKey for the same key (cross-language tested).
		def pubkey
			@pubkey ||= ECDSA::Format::PointOctetString.encode(public_point, compression: true).unpack1("H*")
		end

		private

		def public_point
			ECDSA::Group::Secp256k1.generator.multiply_by_scalar(private_key.to_i(16))
		end
	end
end
