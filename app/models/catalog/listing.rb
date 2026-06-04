# frozen_string_literal: true

require "bigdecimal"
require "digest"

module Catalog
	# Presents a kind-30402 Event as a catalog service listing, reading NIP-99 and
	# service-listing-microstandard (brief §7.1) tags. Every accessor tolerates
	# absent tags.
	class Listing
		MARKER       = "switchboard-service"
		CAPABILITY_L = "capability"

		attr_reader :event

		def initialize(event)
			@event = event
		end

		def title = event.tag("title").presence || "Untitled service"
		def summary = event.tag("summary").presence || description.truncate(140)
		def description = event.content.to_s
		def status = event.tag("status").presence || "active"
		def image = event.tag("image")
		# Fulfillment mode (microstandard, brief §7.1): "automated" | "manual" | nil.
		def fulfillment = event.tag("fulfillment")
		def conforms? = event.tag_values("t").include?(MARKER)

		# NIP-99 price tag: ["price", amount, currency, frequency?]. Amount must be a
		# plain integer/decimal string (Integer() would mangle hex/underscore forms).
		def price_amount
			amount = price_tag[1].to_s
			return unless amount.match?(/\A\d+(\.\d+)?\z/)

			amount.include?(".") ? BigDecimal(amount) : amount.to_i
		end

		def price_currency = price_tag[2].presence || "sat"
		def price? = price_amount.present?

		# Microstandard capability: ["l", value, "<ns>.capability"].
		def capability
			event.tags.find { |t| t.is_a?(Array) && t[0] == "l" && t[2].to_s.end_with?(CAPABILITY_L) }&.dig(1)
		end

		# Microstandard input schema: one ["input_schema", "<JSON array>"] tag (brief §7.1).
		# Each field is { label:, type:, required: }. Tolerates absent / malformed tags.
		def input_schema
			raw = event.tag("input_schema")
			return [] if raw.blank?

			Array(JSON.parse(raw)).filter_map do |field|
				next unless field.is_a?(Hash)

				{ label: field["label"].to_s, type: field["type"].to_s, required: field["required"] == true }
			end
		rescue JSON::ParserError
			[]
		end

		def provider_npub
			Nostr::Bech32.npub_encode(event.pubkey)
		rescue StandardError
			event.pubkey
		end

		# DOM id derived from the addressable coordinate, stable across re-publishes.
		def dom_id = "listing_#{Digest::SHA256.hexdigest(coordinate)[0, 16]}"

		# Lowercased haystack for the client-side catalog filter.
		def search_text = [ title, description, capability ].compact.join(" ").downcase

		# True when search_text contains the free-text query (case-insensitive).
		def matches?(query) = search_text.include?(query.to_s.downcase)

		# Mode bucket for the All / Automated / Human filter ("unknown" when untagged).
		def filter_mode = fulfillment.presence || "unknown"

		private

		def coordinate = "#{event.kind}:#{event.pubkey}:#{event.d_tag}"
		def price_tag = event.tags.find { |t| t.is_a?(Array) && t[0] == "price" } || []
	end
end
