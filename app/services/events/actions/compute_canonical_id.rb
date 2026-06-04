# frozen_string_literal: true

require "json"
require "digest"

module Events
	module Actions
		# The NIP-01 event id: SHA256 of the canonical JSON [0, pubkey, created_at, kind, tags,
		# content]. JSON.generate (never to_json / JSON.dump): it keeps &, <, > literal so the id
		# matches what every relay and nostr-tools compute. The one serializer shared by
		# Events::Verify, Events::Sign, and the messaging services, so a locally built id can
		# never drift from the value re-verification expects.
		class ComputeCanonicalId < BaseService
			option :event, type: Types::Strict::Hash

			def call
				data = event.transform_keys(&:to_s)
				fields = data.values_at("pubkey", "created_at", "kind", "tags", "content")
				Digest::SHA256.hexdigest(JSON.generate([ 0, *fields ]))
			rescue JSON::GeneratorError
				# A field that survives JSON.parse but not JSON.generate (e.g. an invalid-encoding
				# string). Constant message: never interpolate the offending bytes into the error.
				raise InvalidEventError, "event is not canonicalizable (invalid encoding)"
			end
		end
	end
end
