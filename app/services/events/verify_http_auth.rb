# frozen_string_literal: true

require "digest"

module Events
	# Verifies a NIP-98 (kind 27235) HTTP-auth event: structure + canonical id + BIP-340
	# signature (Events::Verify), then the NIP-98 gates: kind, freshness, the `method` and
	# `u` tags bound to the request, and the `payload` body hash when a body is present.
	# Returns the verified, string-keyed event hash. Shared by both auth paths: the browser
	# session (Sessions::Authenticate) and the stateless API path (Sessions::AuthenticateRequest).
	class VerifyHttpAuth < BaseService
		TIMESTAMP_WINDOW = 60 # seconds (NIP-98 suggestion)

		option :event_data, type: Types::Strict::Hash
		option :http_method, type: Types::Strict::String           # the request method, e.g. "POST"
		option :url, type: Types::Strict::String                   # the canonical request URL
		option :body, type: Types::Strict::String.optional, default: -> { } # raw request body, if any

		def call
			data = Events::Verify.call(event_data:)
			verify_kind(data)
			verify_timestamp(data)
			verify_tag(data, "method") { |value| value == http_method }
			verify_tag(data, "u") { |value| normalize(value) == normalize(url) }
			verify_tag(data, "payload") { |value| value == Digest::SHA256.hexdigest(body) } if body.present?
			data
		end

		private

		def verify_kind(data)
			raise AuthenticationError, "wrong kind" unless data["kind"] == Events::Kinds::HTTP_AUTH
		end

		def verify_timestamp(data)
			raise AuthenticationError, "stale timestamp" if (Time.now.to_i - data["created_at"]).abs > TIMESTAMP_WINDOW
		end

		def verify_tag(data, name)
			raise AuthenticationError, "#{name} mismatch" unless yield(tag(data, name).to_s)
		end

		# Reads the first value of a named tag, tolerating a malformed tags array.
		def tag(event, name)
			tags = event["tags"]
			return unless tags.is_a?(Array)

			tags.find { |t| t.is_a?(Array) && t[0] == name }&.dig(1)
		end

		def normalize(value) = value.to_s.strip.downcase.gsub(%r{/+\z}, "")
	end
end
