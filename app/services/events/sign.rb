# frozen_string_literal: true

require "nostr"

module Events
	# Signs a NIP-01 event with a hex private key: derives the x-only pubkey, computes the
	# id via the shared canonical serializer (Events::Actions::ComputeCanonicalId), and signs THAT
	# id with sign_message. Deliberately NOT the nostr gem's sign_event, whose internal
	# hashing path diverges from Events::Verify's JSON.generate id (they disagree on &<>).
	# Returns a string-keyed signed event hash that passes Events::Verify.
	class Sign < BaseService
		option :private_key, type: Types::Strict::String
		option :kind, type: Types::Strict::Integer
		option :content, type: Types::Strict::String
		option :tags, default: -> { [] }
		option :created_at, type: Types::Strict::Integer, default: -> { Time.now.to_i }

		def call
			event = { "pubkey" => pubkey, "created_at" => created_at, "kind" => kind, "tags" => tags, "content" => content }
			event["id"] = Events::Actions::ComputeCanonicalId.call(event:)
			event["sig"] = Nostr::Crypto.new.sign_message(event["id"], keypair.private_key).to_s
			event
		end

		private

		def pubkey = keypair.public_key.to_s

		def keypair
			@keypair ||= Nostr::Keygen.new.get_key_pair_from_private_key(Nostr::PrivateKey.new(private_key))
		end
	end
end
