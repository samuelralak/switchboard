# frozen_string_literal: true

module Catalog
	# Builds an in-memory Catalog::Listing from provider-studio form params, for the on-demand buyer
	# preview the studio renders in a drawer. It mirrors the kind-30402 tag shape the browser publisher
	# signs (NIP-99 + the service-listing microstandard, brief §7.1), so the preview renders the very
	# component the catalog uses. It is render-equivalent, NOT byte-equivalent: the canonical wire format is
	# listing_publish.js buildEvents. Deliberate divergences for a preview (none reach the catalog):
	#   - d: a literal "preview" placeholder; the real d-tag is random (or carried on edit), unknowable here.
	#   - no created_at / id / signature: this is an unsaved, unsigned Event.
	#   - no status / published_at tags: visibility/carry metadata the buyer preview does not render.
	# The tag head, image machinery, param lookup, title, and the preview factory live in Events::Draftable;
	# this keeps only the listing's divergent body tags (price with an optional frequency, fulfillment,
	# endpoint, the manual delivery window, the input schema). Pure: builds an unsaved Event, never the DB.
	class Draft
		include Events::Draftable

		# A Catalog::Listing over an unsaved kind-30402 Event, attributed to the previewing provider.
		def self.listing(params, pubkey: nil) = preview(params, pubkey:)

		def self.presenter_class = Catalog::Listing

		private

		def body_tags_order
			%i[capability_tag price_tag fulfillment_tag endpoint_tag delivery_window_tag input_schema_tag]
		end

		# NIP-99 price tag ["price", amount, "sat", frequency?]; the optional 4th element is the recurring
		# frequency ("hour"). Listing-only: a request's budget is a fixed amount with no frequency, built by
		# Requests::Draft#budget_tag, kept separate so a frequency can never leak onto a budget.
		def price_tag
			price = field(:price)
			return if price.blank?

			tag = [ "price", price.to_s, "sat" ]
			freq = field(:price_frequency)
			freq.present? ? tag << freq : tag
		end

		def fulfillment_tag
			mode = field(:fulfillment)
			[ "fulfillment", mode ] if mode.present?
		end

		def endpoint_tag
			url = field(:endpoint)
			[ "endpoint", url ] if field(:fulfillment) == "automated" && url.present?
		end

		# Manual delivery window only: gated on fulfillment == "manual" (an automated service forwards to
		# its endpoint instead). The request emits its window unconditionally; this gate is listing-only.
		def delivery_window_tag
			value = field(:delivery_value)
			return unless field(:fulfillment) == "manual" && value.present?

			[ "delivery_window", window_suffix(value, field(:delivery_unit)) ]
		end

		# One ["input_schema", <JSON array>] tag of { name, label, type, required } objects (never one
		# tag per field). required is emitted as a real JSON boolean (the reader checks `== true`).
		def input_schema_tag
			rows = schema_rows
			return if rows.empty?

			[ "input_schema", rows.to_json ]
		end

		def schema_rows
			Array(field(:schema)).filter_map { |row| normalize_row(row) }
		end

		# One schema row -> { name, label, type, required }, or nil when it carries neither name nor label.
		def normalize_row(row)
			return unless row.respond_to?(:symbolize_keys)

			row = row.symbolize_keys
			return if row[:label].to_s.blank? && row[:name].to_s.blank?

			{ name: row[:name].to_s, label: row[:label].to_s, type: row[:type].to_s, required: truthy?(row[:required]) }
		end
	end
end
