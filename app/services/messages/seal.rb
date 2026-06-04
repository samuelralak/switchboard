# frozen_string_literal: true

module Messages
	# NIP-59 seal (kind 13): the rumor JSON, NIP-44-encrypted to the recipient under the
	# author's own conversation key, then signed by the author. Tags MUST be empty (the only
	# public information is who signed it, never the recipient or content), and created_at is
	# randomized into the past. Signed through Events::Sign so the id uses the shared
	# canonical serializer, never the gem's divergent re-hashing.
	class Seal < BaseService
		option :rumor, type: Types::Strict::Hash
		option :author_private_key, type: Types::Strict::String # hex
		option :recipient_pubkey, type: Types::Strict::String   # x-only hex
		option :created_at, type: Types::Strict::Integer, default: -> { Actions::RandomPastTimestamp.call }

		def call
			conversation_key = Nip44.conversation_key(author_private_key, recipient_pubkey)
			content = Nip44.encrypt(JSON.generate(rumor), conversation_key)
			Events::Sign.call(private_key: author_private_key, kind: Events::Kinds::SEAL, tags: [], content:, created_at:)
		end
	end
end
