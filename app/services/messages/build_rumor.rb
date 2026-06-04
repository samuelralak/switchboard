# frozen_string_literal: true

module Messages
	# Builds an UNSIGNED NIP-17 rumor (kind 14 chat, kind 15 file): the user-visible event
	# carrying an id but NO signature (NIP-59: the inner event MUST always be unsigned, so a
	# leaked rumor cannot be authenticated). created_at is the canonical REAL time (only the
	# seal and wrap are randomized into the past). pubkey is the real author, the anchor the
	# anti-impersonation check enforces on unwrap (seal.pubkey == rumor.pubkey).
	class BuildRumor < BaseService
		option :author_pubkey, type: Types::Strict::String # x-only hex
		option :content, type: Types::Strict::String
		option :recipients, default: -> { [] } # x-only hex pubkeys -> p tags
		option :kind, type: Types::Strict::Integer, default: -> { Events::Kinds::DIRECT_MESSAGE }
		option :subject, type: Types::Strict::String.optional, default: -> { }
		option :reply_to, type: Types::Strict::String.optional, default: -> { } # parent event id -> e tag
		option :created_at, type: Types::Strict::Integer, default: -> { Time.now.to_i }

		def call
			rumor = { "pubkey" => author_pubkey, "created_at" => created_at, "kind" => kind }
			rumor["tags"] = tags
			rumor["content"] = content
			rumor["id"] = Events::Actions::ComputeCanonicalId.call(event: rumor)
			rumor # intentionally unsigned
		end

		private

		def tags
			t = Array(recipients).map { |pk| [ "p", pk ] }
			t << [ "e", reply_to ] if reply_to
			t << [ "subject", subject ] if subject
			t
		end
	end
end
