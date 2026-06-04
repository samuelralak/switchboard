# frozen_string_literal: true

module Messages
	# Reverses a NIP-59 gift wrap with the recipient's private key and returns the validated,
	# string-keyed rumor (only the six canonical fields). Enforces every NIP-17/59 MUST:
	#   * the wrap (kind 1059) and seal (kind 13) are SIGNED -> full NIP-01 verify (id + sig);
	#   * the seal's tags are empty;
	#   * the rumor is UNSIGNED -> it CANNOT go through Events::Verify (which requires a sig),
	#     so it is validated here directly: NIP-01 typing, no NUL bytes, an id that recomputes
	#     over the canonical fields, and no smuggled extra keys (those the id never covers);
	#   * seal.pubkey == rumor.pubkey -> without this any sender forges authorship (NIP-17).
	# Raises Messages::UnwrapError on any violation (decrypt failure, bad sig, forged rumor),
	# so the ingest job discards adversarial/undecryptable wraps instead of retrying them.
	class Unwrap < BaseService
		RUMOR_FIELDS = %w[id pubkey created_at kind tags content].freeze

		option :gift_wrap, type: Types::Strict::Hash
		option :recipient_private_key, type: Types::Strict::String # hex

		def call
			wrap = verify_signed(gift_wrap, Events::Kinds::GIFT_WRAP, "gift wrap")
			seal = verify_signed(decrypt(wrap["content"], wrap["pubkey"]), Events::Kinds::SEAL, "seal")
			raise UnwrapError, "seal tags must be empty" unless seal["tags"] == []

			validated_rumor(decrypt(seal["content"], seal["pubkey"]), seal)
		end

		private

		# A signed layer (wrap or seal): full NIP-01 verification, then the kind gate.
		def verify_signed(event, expected_kind, label)
			data = Events::Verify.call(event_data: event)
			raise UnwrapError, "#{label}: expected kind #{expected_kind}" unless data["kind"] == expected_kind

			data
		rescue InvalidEventError => e
			raise UnwrapError, "#{label}: #{e.message}"
		end

		# NIP-44-decrypt content under conversation_key(recipient_priv, sender_pubkey) and parse
		# the inner JSON event. The conversation key is symmetric, so deriving it against the
		# outer event's (signature-verified) pubkey recovers exactly what the sender encrypted.
		def decrypt(ciphertext, sender_pubkey)
			parsed = JSON.parse(Nip44.decrypt(ciphertext.to_s, Nip44.conversation_key(recipient_private_key, sender_pubkey)))
			raise UnwrapError, "decrypted layer is not an object" unless parsed.is_a?(Hash)

			parsed
		rescue Nip44::Error => e
			raise UnwrapError, "decrypt failed: #{e.message}" # Nip44 messages are static, no plaintext
		rescue JSON::ParserError
			raise UnwrapError, "decrypted layer is not valid JSON" # never interpolate: e.message embeds plaintext
		end

		# The rumor is unsigned: validate it WITHOUT Events::Verify (which demands a sig). Type
		# checks run first; the id is recomputed next (safe because it ignores any "sig" key and
		# JSON.generate escapes a NUL rather than raising); then the sig and NUL guards run. The
		# result is sliced to the six fields the id covers (any extra key is unauthenticated).
		def validated_rumor(rumor, seal)
			assert_typed!(rumor)
			id = canonical_id(rumor)
			raise UnwrapError, "rumor must be unsigned" if rumor.key?("sig")
			raise UnwrapError, "rumor contains null bytes" if Shared::ContainsNullByte.call(value: rumor)
			raise UnwrapError, "rumor id mismatch" unless id == rumor["id"]
			raise UnwrapError, "impersonation: seal.pubkey != rumor.pubkey" unless seal["pubkey"] == rumor["pubkey"]

			rumor.slice(*RUMOR_FIELDS)
		end

		# The rumor id. A rumor that cannot be canonicalized (e.g. a lone-surrogate \u escape that
		# survives JSON.parse but breaks JSON.generate) maps to UnwrapError so it is discarded, not
		# retried, like every other rumor violation.
		def canonical_id(rumor)
			Events::Actions::ComputeCanonicalId.call(event: rumor)
		rescue InvalidEventError => e
			raise UnwrapError, "rumor: #{e.message}"
		end

		# NIP-01 typing the signed layers get from Events::Verify but the unsigned rumor skips:
		# id/pubkey/content strings, created_at/kind integers, tags an array (missing -> nil -> fails).
		def assert_typed!(rumor)
			strings = rumor.values_at("id", "pubkey", "content").all?(String)
			integers = rumor.values_at("created_at", "kind").all?(Integer)
			raise UnwrapError, "rumor has malformed NIP-01 fields" unless strings && integers && rumor["tags"].is_a?(Array)
		end
	end
end
