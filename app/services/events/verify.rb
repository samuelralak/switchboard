# frozen_string_literal: true

require "nostr"
require "json"
require "digest"

module Events
	# Validates an inbound event's structure (Contract), its id (NIP-01 canonical
	# hash), and its BIP-340 Schnorr signature. Returns the normalized string-keyed
	# event hash; raises InvalidEventError on any failure.
	class Verify < BaseService
		option :event_data, type: Types::Strict::Hash

		def call
			@data = event_data.transform_keys(&:to_s)

			result = Contract.new.call(@data)
			raise InvalidEventError, "structure: #{result.errors(full: true).map(&:text).join(', ')}" unless result.success?
			raise InvalidEventError, "contains null bytes" if Shared::ContainsNullByte.call(value: @data)
			raise InvalidEventError, "created_at and kind must be integers" unless integer_typed?
			raise InvalidEventError, "id mismatch" unless id_valid?
			raise InvalidEventError, "bad signature" unless signature_valid?

			@data
		end

		private

		# NIP-01 created_at and kind are integers; the raw value feeds the canonical id,
		# so a coerced string/float would hash to an id no relay can reproduce.
		def integer_typed?
			@data["created_at"].is_a?(Integer) && @data["kind"].is_a?(Integer)
		end

		def id_valid?
			Events::Actions::ComputeCanonicalId.call(event: @data) == @data["id"]
		end

		def signature_valid?
			Nostr::Crypto.new.valid_sig?(
				@data["id"],
				Nostr::PublicKey.new(@data["pubkey"]),
				Nostr::Signature.new(@data["sig"])
			)
		rescue StandardError => e
			raise InvalidEventError, "bad signature (#{e.class}: #{e.message})"
		end
	end
end
