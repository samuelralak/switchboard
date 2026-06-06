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
	# Pure: it builds an unsaved Event and never touches the database. Lenient by design (it previews
	# whatever is present); strict publish validation lives client-side + in the publisher.
	class Draft
		# A Catalog::Listing over an unsaved kind-30402 Event, attributed to the previewing provider.
		def self.listing(params, pubkey: nil)
			attrs = { kind: Events::Kinds::CLASSIFIED, pubkey: pubkey.to_s, content: value(params, :description), tags: new(params).tags }
			Catalog::Listing.new(Event.new(**attrs))
		end

		# Normalized lookup tolerating string/symbol keys and ActionController::Parameters.
		def self.value(params, key) = params[key.to_s].presence || params[key.to_sym].presence

		def initialize(params)
			@params = params
		end

		# The kind-30402 tag set in the publisher tag order (minus the carry-only status/published_at and the
		# signed-only fields); nil entries are dropped.
		def tags
			result = [ %w[d preview], [ "title", title ], [ "t", Catalog::Listing.marker ] ]
			result.push(capability_tag, price_tag, fulfillment_tag)
			result.push(endpoint_tag, delivery_window_tag, input_schema_tag)
			(result + image_tags).compact
		end

		private

		attr_reader :params

		def field(key) = self.class.value(params, key)

		def title = field(:title).presence || "Untitled service"

		def capability_tag
			cap = field(:capability)
			[ "l", cap, Catalog::Listing::CAPABILITY_NAMESPACE ] if cap.present?
		end

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

		# Manual delivery window: a value + unit (hours/days) collapse to the microstandard "24h" / "3d".
		def delivery_window_tag
			value = field(:delivery_value)
			return unless field(:fulfillment) == "manual" && value.present?

			[ "delivery_window", "#{value}#{field(:delivery_unit) == 'days' ? 'd' : 'h'}" ]
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

		# Each picked image becomes an ["image", url] tag (the cover is the first) plus a NIP-92 imeta tag
		# carrying url/m/x/dim. Tolerates plain-string URLs as well as { url:, m:, x:, dim: } hashes.
		def image_tags
			images.flat_map do |img|
				tags = [ [ "image", img[:url] ] ]
				tags << imeta_tag(img) if img.values_at(:m, :x, :dim).any?(&:present?)
				tags
			end
		end

		def images
			Array(field(:images)).filter_map { |img| normalize_image(img) }
		end

		def normalize_image(img)
			return { url: img } if img.is_a?(String) && img.present?
			return unless img.respond_to?(:symbolize_keys)

			img = img.symbolize_keys
			{ url: img[:url].to_s, m: img[:m].to_s, x: img[:x].to_s, dim: img[:dim].to_s } if img[:url].to_s.present?
		end

		def imeta_tag(img)
			parts = [ "imeta", "url #{img[:url]}" ]
			%i[m x dim].each { |key| parts << "#{key} #{img[key]}" if img[key].present? }
			parts
		end

		def truthy?(value) = [ true, "true", "1", "on" ].include?(value)
	end
end
