# frozen_string_literal: true

require "nostr"

module Operational
	# The R_op operational key: the runtime's OWN low-privilege Nostr identity, used to sign
	# platform speech (NIP-42 relay AUTH, NIP-89 handler info, R_op's own NIP-17 messages).
	# NEVER a user key and it never holds funds (the non-custodial invariant). The hex key is read
	# from ENV (R_OP_PRIVATE_KEY) and is touched ONLY here; its reader is private so the key cannot
	# leak. Signs through Events::Sign for canonical-id parity.
	class Signer
		extend Dry::Initializer

		ENV_VAR = "R_OP_PRIVATE_KEY"

		option :private_key, type: Types::Strict::String, reader: :private, default: -> { self.class.env_key }

		# True when the R_op key is present in ENV (gates wiring it as the relay auth_signer).
		def self.configured? = ENV.fetch(ENV_VAR, nil).present?

		def self.env_key
			key = ENV.fetch(ENV_VAR, nil)
			raise(KeyError, "R_op key missing: set #{ENV_VAR} (64-hex)") if key.blank?

			key
		end

		def pubkey
			@pubkey ||= keypair.public_key.to_s
		end

		def sign(kind:, content: "", tags: [], created_at: Time.now.to_i)
			Events::Sign.call(private_key:, kind:, content:, tags:, created_at:)
		end

		private

		def keypair
			@keypair ||= Nostr::Keygen.new.get_key_pair_from_private_key(Nostr::PrivateKey.new(private_key))
		end
	end
end
