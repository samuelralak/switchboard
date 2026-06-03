# frozen_string_literal: true

module Events
	# Derives the indexed columns from the raw event before validation:
	# first_seen_at, the addressable d-tag, and the NIP-40 expiry.
	module Ingestable
		extend ActiveSupport::Concern

		MAX_EXPIRY = 253_402_300_799 # 9999-12-31 UTC; keeps expires_at within column range

		included do
			before_validation :set_first_seen_at, on: :create
			before_validation :set_d_tag
			before_validation :set_expires_at
		end

		private

		def set_first_seen_at
			self.first_seen_at ||= Time.current
		end

		# Addressable events (NIP-01 30000-39999) are keyed by their `d` tag; a
		# missing d tag means d="" per NIP-01. Non-addressable kinds stay nil.
		def set_d_tag
			return unless kind && Events::Kinds.addressable?(kind)

			tag = tags&.find { |t| d_tag?(t) }
			self.d_tag = tag ? tag[1].to_s : ""
		end

		def d_tag?(tag)
			tag.is_a?(Array) && tag[0] == "d" && !tag[1].nil?
		end

		# NIP-40: an ["expiration", "<unix>"] tag sets expires_at. An absurd far-future
		# value is treated as non-expiring so it cannot overflow the timestamp column.
		def set_expires_at
			tag = tags&.find { |t| t.is_a?(Array) && t[0] == "expiration" }
			unix = tag&.dig(1).to_i
			self.expires_at = (Time.at(unix).utc if unix.positive? && unix <= MAX_EXPIRY)
		end
	end
end
