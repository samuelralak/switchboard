# frozen_string_literal: true

# NIP-98 `Authorization: Nostr <base64-event>` handling, shared by the browser session
# controller (which only decodes) and stateless API controllers (which authenticate
# per request).
module Nip98Authentication
	extend ActiveSupport::Concern

	private

	# Authenticates a stateless API request from its Authorization header, setting
	# Current.user. Renders 401 on any failure, without disclosing which gate failed.
	def authenticate_request!
		event = decode_nip98_event(request.headers["Authorization"])
		Current.authenticated_user = Sessions::AuthenticateRequest.call(**verify_args(event))
	rescue AuthenticationError, InvalidEventError
		head :unauthorized
	end

	# btoa emits standard, padded base64, so strict_decode64 matches it and rejects
	# anything else; a malformed header becomes a typed AuthenticationError.
	def decode_nip98_event(header)
		scheme, encoded = header.to_s.split(" ", 2)
		raise AuthenticationError, "missing Nostr authorization" unless scheme&.casecmp?("Nostr") && encoded.present?

		event = JSON.parse(Base64.strict_decode64(encoded))
		raise AuthenticationError, "auth event is not an object" unless event.is_a?(Hash)

		event
	rescue ArgumentError, JSON::ParserError
		raise AuthenticationError, "malformed authorization header"
	end

	# The `u` URL is pinned to the canonical origin + the full request path including the
	# query (original_fullpath), never request.url/Host (a proxy could spoof those); the body
	# binds write-method payloads. The client signs exactly this URL and method.
	def verify_args(event)
		url = "#{Rails.application.config.x.canonical_origin}#{request.original_fullpath}"
		{ event_data: event, http_method: request.request_method, url:, body: request.raw_post }
	end
end
