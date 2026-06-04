# frozen_string_literal: true

require "nostr"

module Messages
	# NIP-59 gift wrap (kind 1059): the seal JSON, NIP-44-encrypted under a FRESH single-use
	# ephemeral key (never reused across recipients, so wraps and the recipient set cannot be
	# linked), signed by that ephemeral key, with a single ["p", recipient] routing tag and
	# an independently randomized past created_at. The ephemeral private key never leaves
	# this call. Wrap separately for each recipient (and, if kept, the sender's own copy).
	class GiftWrap < BaseService
		option :seal, type: Types::Strict::Hash
		option :recipient_pubkey, type: Types::Strict::String # x-only hex
		option :relay_url, type: Types::Strict::String.optional, default: -> { }
		option :created_at, type: Types::Strict::Integer, default: -> { Actions::RandomPastTimestamp.call }

		def call
			secret_key = Nostr::Keygen.new.generate_key_pair.private_key.to_s
			conversation_key = Nip44.conversation_key(secret_key, recipient_pubkey)
			content = Nip44.encrypt(JSON.generate(seal), conversation_key)
			Events::Sign.call(private_key: secret_key, kind: Events::Kinds::GIFT_WRAP, tags: [ p_tag ], content:, created_at:)
		end

		private

		def p_tag
			relay_url ? [ "p", recipient_pubkey, relay_url ] : [ "p", recipient_pubkey ]
		end
	end
end
