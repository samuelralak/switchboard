# frozen_string_literal: true

require "bigdecimal"
require "digest"

module Catalog
	# Presents a kind-30402 Event as a catalog service listing, reading NIP-99 and
	# service-listing-microstandard (brief §7.1) tags. Every accessor tolerates
	# absent tags.
	class Listing
		BASE_MARKER  = "switchboard-service"
		CAPABILITY_L = "capability"
		# NIP-32 namespace for the capability label tag ["l", value, CAPABILITY_NAMESPACE]. The reader
		# stays lenient (matches any namespace ending in CAPABILITY_L), but the publisher + draft emit
		# this one canonical value.
		CAPABILITY_NAMESPACE = "service.capability"

		# The service marker tag, scoped by environment so development/staging/test listings never
		# pollute the production catalog (production is the bare marker; other envs are suffixed). One
		# source of truth, used by conforms?, the publisher, and the conformance badge.
		def self.marker
			Rails.env.production? ? BASE_MARKER : "#{BASE_MARKER}-#{Rails.env}"
		end

		attr_reader :event

		def initialize(event)
			@event = event
		end

		def title = event.tag("title").presence || "Untitled service"
		def summary = event.tag("summary").presence || description.truncate(140)
		def description = event.content.to_s
		def status = event.tag("status").presence || "active"
		# Live in the public catalog? Unpublishing re-publishes the same coordinate with status="inactive".
		def active? = status == "active"
		# Original publish time (NIP-99); carried through edits so it is not reset on re-publish.
		def published_at = event.tag("published_at")
		# The addressable `d` identifier (the listing's stable id across re-publishes/edits).
		def identifier = event.tag("d").to_s
		# Cover image, restricted to http(s): a foreign listing could carry a javascript:/data: url, and
		# this value flows into an <img src>. Defense-in-depth on top of ERB escaping + the CSP img-src.
		def image = http_url(event.tag("image"))
		# Fulfillment mode (microstandard, brief §7.1): "automated" | "manual" | nil.
		def fulfillment = event.tag("fulfillment")
		# Automated endpoint (microstandard): the runtime forwards each paid request here.
		def endpoint = event.tag("endpoint")
		# Manual delivery window (microstandard): e.g. "24h" / "3d"; sets the acceptance deadline clock.
		def delivery_window = event.tag("delivery_window")
		# All listing images (NIP-99 image tags, http(s) only); the first is the cover.
		def images = event.tags.select { |t| t.is_a?(Array) && t[0] == "image" }.filter_map { |t| http_url(t[1]) }
		def conforms? = event.tag_values("t").include?(self.class.marker)

		# NIP-99 price tag: ["price", amount, currency, frequency?]. Amount must be a
		# plain integer/decimal string (Integer() would mangle hex/underscore forms).
		def price_amount
			amount = price_tag[1].to_s
			return unless amount.match?(/\A\d+(\.\d+)?\z/)

			amount.include?(".") ? BigDecimal(amount) : amount.to_i
		end

		def price_currency = price_tag[2].presence || "sat"
		def price? = price_amount.present?

		# NIP-99 optional recurring frequency (the 4th price element): "hour", "day", etc. We author only
		# "hour" (per-hour) vs none (per-request), but display whatever a listing carries.
		def price_frequency = price_tag[3].presence
		def per_hour? = price_frequency == "hour"

		# The PriceTag unit suffix: "sat", or "sat / hr" for a per-hour (or other recurring) listing.
		FREQ_SHORT = { "hour" => "hr", "day" => "day", "week" => "wk", "month" => "mo", "year" => "yr" }.freeze
		def price_suffix
			return price_currency unless price_frequency

			"#{price_currency} / #{FREQ_SHORT[price_frequency] || price_frequency}"
		end

		# Microstandard capability: ["l", value, "<ns>.capability"].
		def capability
			event.tags.find { |t| t.is_a?(Array) && t[0] == "l" && t[2].to_s.end_with?(CAPABILITY_L) }&.dig(1)
		end

		# Microstandard input schema: one ["input_schema", "<JSON array>"] tag (brief §7.1). Each field is
		# { name:, label:, type:, required: }: name is the stable request/endpoint/interop key, label the
		# human prompt. name is optional-tolerant on read (falls back to a slug of label) so older or
		# foreign listings still parse. Tolerates absent / malformed tags.
		def input_schema
			raw = event.tag("input_schema")
			return [] if raw.blank?

			Array(JSON.parse(raw)).filter_map { |field| input_field(field) if field.is_a?(Hash) }
		rescue JSON::ParserError
			[]
		end

		# NIP-92 imeta metadata for an image url: { url:, m:, x:, dim:, blurhash:, alt: } (present keys
		# only), or {} when the listing has no matching imeta tag.
		def image_meta(url)
			tag = imeta_tag(url)
			return {} unless tag

			tag.drop(1).each_with_object({}) do |pair, meta|
				key, value = pair.to_s.split(" ", 2)
				meta[key.to_sym] = value if key.present? && value.present?
			end
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

		# A url only if it is http(s); otherwise nil (keeps javascript:/data: urls out of <img src>).
		def http_url(url) = url.to_s.match?(%r{\Ahttps?://}i) ? url : nil

		# snake_case slug for an input-schema field name derived from its label.
		def slugify(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence || "field"

		# One input-schema field, read-tolerant: name falls back to a slug of the label (brief §7.1).
		def input_field(field)
			label = field["label"].to_s
			name = field["name"].presence || slugify(label)
			{ name:, label:, type: field["type"].to_s, required: field["required"] == true }
		end

		def imeta_tag(url)
			event.tags.find { |t| t.is_a?(Array) && t[0] == "imeta" && t.include?("url #{url}") }
		end
	end
end
