# frozen_string_literal: true

module Catalog
	# Presents a kind-30402 Event as a catalog service listing, reading NIP-99 and the service-listing
	# microstandard (brief §7.1). Shared NIP-99 reading (title/summary/images/capability/price-tag amount/
	# coordinate/search) lives in Events::Nip99Presentation; this adds the listing's own vocabulary: pricing
	# basis, fulfillment, and the input schema. Every accessor tolerates absent tags.
	class Listing
		include Events::Nip99Presentation

		BASE_MARKER   = "switchboard-service"
		DEFAULT_TITLE = "Untitled service"
		DOM_PREFIX    = "listing"

		# NIP-32 namespace for the capability label tag ["l", value, CAPABILITY_NAMESPACE]. The reader stays
		# lenient (Nip99Presentation matches any namespace ending in CAPABILITY_L), but the publisher + draft
		# emit this one canonical value.
		CAPABILITY_NAMESPACE = "service.capability"

		# Live in the public catalog? Unpublishing re-publishes the same coordinate with status="inactive".
		def active? = status == "active"

		# The catalog provider, as an npub.
		def provider_npub = author_npub

		# NIP-99 price tag ["price", amount, currency, frequency?]. Amount must be a plain integer / decimal.
		def price_amount = parse_amount(price_tag[1])
		def price_currency = price_tag[2].presence || "sat"
		def price? = price_amount.present?

		# Escrow locks whole sats, so only a fixed positive whole-sat price is orderable. The UI order gate
		# (Catalog::ServiceDetail) and the server enforcement (Orders::Place) read this one rule.
		def whole_sat_price? = whole_sat?(price_amount, price_currency)

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

		# Fulfillment mode (microstandard, brief §7.1): "automated" | "manual" | nil.
		def fulfillment = event.tag("fulfillment")
		# Automated endpoint delivery is not orderable yet (no dispatcher); the single rule both the buyer UI
		# and the server order path read, so an automated listing cannot be ordered via either.
		def automated? = fulfillment == "automated"
		# Automated endpoint (microstandard): the runtime forwards each paid request here.
		def endpoint = event.tag("endpoint")
		# Manual delivery window (microstandard): e.g. "24h" / "3d"; sets the acceptance deadline clock.
		def delivery_window = event.tag("delivery_window")
		# Mode bucket for the All / Automated / Human filter ("unknown" when untagged).
		def filter_mode = fulfillment.presence || "unknown"

		# Microstandard input schema: one ["input_schema", "<JSON array>"] tag (brief §7.1). Each field is
		# { name:, label:, type:, required: }: name is the stable request/endpoint/interop key, label the
		# human prompt. name is optional-tolerant on read (falls back to a slug of label) so older or foreign
		# listings still parse. Tolerates absent / malformed tags.
		def input_schema
			raw = event.tag("input_schema")
			return [] if raw.blank?

			Array(JSON.parse(raw)).filter_map { |field| input_field(field) if field.is_a?(Hash) }
		rescue JSON::ParserError
			[]
		end

		private

		# snake_case slug for an input-schema field name derived from its label.
		def slugify(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence || "field"

		# One input-schema field, read-tolerant: name falls back to a slug of the label (brief §7.1).
		def input_field(field)
			label = field["label"].to_s
			name = field["name"].presence || slugify(label)
			{ name:, label:, type: field["type"].to_s, required: field["required"] == true }
		end
	end
end
