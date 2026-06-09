# frozen_string_literal: true

module Sessions
	# Browser sign-in: verifies a NIP-98 event bound to a server-issued single-use nonce
	# and returns the User. The nonce (from the `challenge` tag) is consumed before the
	# signature check, so a replay flood dies before any curve operation; its presence in
	# the signed tags binds the signature to it.
	class Authenticate < BaseService
		option :event_data, type: Types::Strict::Hash
		option :http_method, type: Types::Strict::String # the request method, e.g. "POST"
		option :url, type: Types::Strict::String # the canonical verify-endpoint URL

		def call
			nonce = challenge_nonce
			raise AuthenticationError, "challenge unknown, expired, or already used" unless LoginChallenge.consume(nonce)

			data = Events::VerifyHttpAuth.call(event_data:, http_method:, url:)
			user = Users::FindOrCreate.call(pubkey: data["pubkey"])
			# Pull this user's NIP-65 relays into the catalog ingest, off the request path (cooldown-gated).
			Users::RelayListFetchJob.perform_later(user.pubkey)
			user
		end

		private

		def challenge_nonce
			nonce = challenge_tag
			raise AuthenticationError, "missing challenge tag" if nonce.blank?

			nonce
		end

		# Reads the `challenge` tag from the raw (pre-verification) event for the nonce gate.
		def challenge_tag
			tags = event_data["tags"]
			return unless tags.is_a?(Array)

			tags.find { |t| t.is_a?(Array) && t[0] == "challenge" }&.dig(1)
		end
	end
end
