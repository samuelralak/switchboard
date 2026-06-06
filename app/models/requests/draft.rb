# frozen_string_literal: true

module Requests
	# Builds an in-memory Requests::OpenRequest from composer form params, for the on-demand preview the
	# request composer renders in a drawer. Mirrors the kind-30402 tag shape the browser publisher signs
	# (NIP-99 + the request marker), so the preview renders the very component the board uses. It is
	# render-equivalent, NOT byte-equivalent: the canonical wire format is request_publish.js
	# buildRequestEvent. Deliberate divergences for a preview (none reach the board):
	#   - d: a literal "preview" placeholder; the real d-tag is random (or carried on edit), unknowable here.
	#   - no created_at / id / signature: this is an unsaved, unsigned Event.
	#   - no status / published_at tags: visibility/carry metadata the preview does not render.
	# Pure: it builds an unsaved Event and never touches the database. Lenient by design (it previews
	# whatever is present); strict publish validation lives client-side + in the publisher.
	class Draft
		# A Requests::OpenRequest over an unsaved kind-30402 Event, attributed to the previewing consumer.
		def self.open_request(params, pubkey: nil)
			attrs = {
				kind: Events::Kinds::CLASSIFIED, pubkey: pubkey.to_s,
				content: value(params, :description), tags: new(params).tags
			}
			Requests::OpenRequest.new(Event.new(**attrs))
		end

		# Normalized lookup tolerating string/symbol keys and ActionController::Parameters.
		def self.value(params, key) = params[key.to_s].presence || params[key.to_sym].presence

		def initialize(params)
			@params = params
		end

		# The kind-30402 tag set in the publisher tag order (minus the carry-only status/published_at and the
		# signed-only fields); nil entries are dropped.
		def tags
			result = [ %w[d preview], [ "title", title ], [ "t", Requests::OpenRequest.marker ] ]
			result.push(capability_tag, budget_tag, delivery_window_tag, claim_window_tag)
			(result + image_tags).compact
		end

		private

		attr_reader :params

		def field(key) = self.class.value(params, key)

		def title = field(:title).presence || "Untitled request"

		def capability_tag
			cap = field(:capability)
			[ "l", cap, Catalog::Listing::CAPABILITY_NAMESPACE ] if cap.present?
		end

		# The funded budget reuses NIP-99's price tag; a bounty is a single fixed amount (no frequency).
		def budget_tag
			budget = field(:budget)
			[ "price", budget.to_s, "sat" ] if budget.present?
		end

		# Delivery + claim windows collapse a value + unit (hours/days) to the microstandard "48h" / "7d".
		def delivery_window_tag = window_tag("delivery_window", :delivery_value, :delivery_unit)
		def claim_window_tag = window_tag("claim_window", :claim_value, :claim_unit)

		def window_tag(name, value_key, unit_key)
			value = field(value_key)
			return if value.blank?

			[ name, "#{value}#{field(unit_key) == 'days' ? 'd' : 'h'}" ]
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
	end
end
