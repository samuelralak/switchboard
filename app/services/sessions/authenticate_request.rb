# frozen_string_literal: true

module Sessions
	# Stateless per-request auth for non-browser / nsec clients (CLI, agents, runtime):
	# verifies the NIP-98 event, reserves its id once against replay, and returns the User.
	# No session is created. The id is reserved only after the signature verifies, so a
	# forged id cannot poison the replay cache.
	class AuthenticateRequest < BaseService
		option :event_data, type: Types::Strict::Hash
		option :http_method, type: Types::Strict::String
		option :url, type: Types::Strict::String
		option :body, type: Types::Strict::String.optional, default: -> { }
		option :store, default: -> { Rails.cache } # injectable; Rails.cache is the null store under test

		def call
			data = Events::VerifyHttpAuth.call(event_data:, http_method:, url:, body:)
			ReplayGuard.call(event_id: data["id"], store:)
			Users::FindOrCreate.call(pubkey: data["pubkey"])
		end
	end
end
