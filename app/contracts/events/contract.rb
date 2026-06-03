# frozen_string_literal: true

require "dry/validation"

module Events
	# NIP-01 structural validation for an inbound event. Runs before the
	# signature check, and also rejects already-expired (NIP-40) events.
	class Contract < ApplicationContract
		CREATED_AT_GRACE  = 15 * 60 # seconds of future clock skew allowed
		MAX_TAGS          = 2000
		MAX_TAGS_BYTES    = 64 * 1024
		MAX_CONTENT_BYTES = 256 * 1024
		MAX_D_TAG         = 255 # the d_tag column limit

		params do
			required(:id).filled(:string)
			required(:pubkey).filled(:string)
			required(:created_at).filled(:integer)
			required(:kind).filled(:integer)
			required(:tags).value(:array)
			required(:content).value(:string)
			required(:sig).filled(:string)
		end

		rule(:id)     { key.failure("must be 64 lowercase hex") unless Events::Kinds::HEX64.match?(value) }
		rule(:pubkey) { key.failure("must be 64 lowercase hex") unless Events::Kinds::HEX64.match?(value) }
		rule(:sig)    { key.failure("must be 128 lowercase hex") unless Events::Kinds::HEX128.match?(value) }
		rule(:kind)   { key.failure("out of range") unless value.between?(0, 65_535) }

		rule(:created_at) do
			if value.negative?
				key.failure("must be a positive unix timestamp")
			elsif value > Time.now.to_i + CREATED_AT_GRACE
				key.failure("too far in the future")
			end
		end

		rule(:tags) do
			if value.size > MAX_TAGS
				key.failure("too many tags")
			elsif value.sum { |t| Array(t).sum { |x| x.to_s.bytesize } } > MAX_TAGS_BYTES
				key.failure("tags too large")
			elsif value.any? { |t| !t.is_a?(Array) || t.any? { |x| !x.is_a?(String) } }
				key.failure("each tag must be an array of strings")
			elsif (value.find { |t| t[0] == "d" && !t[1].nil? }&.dig(1)).to_s.length > MAX_D_TAG
				key.failure("d tag too long")
			end
		end

		rule(:content) do
			key.failure("content too large") if value.bytesize > MAX_CONTENT_BYTES
		end

		# NIP-40: reject events already past their expiration.
		rule(:tags) do
			exp = value.find { |t| t.is_a?(Array) && t[0] == "expiration" }&.dig(1).to_i
			key.failure("event has expired") if exp.positive? && exp <= Time.now.to_i
		end
	end
end
