# frozen_string_literal: true

module Events
	# Shared builder for the kind-30402 NIP-99 preview events that Catalog::Draft and Requests::Draft both
	# assemble from form params (the on-demand drawer preview). The write-side mirror of Events::
	# Nip99Presentation: that concern is how a Listing and an OpenRequest READ a 30402 event the same way;
	# this is how a Draft BUILDS one the same way. Each includer declares self.presenter_class (Catalog::
	# Listing or Requests::OpenRequest, which carry .marker + ::DEFAULT_TITLE) and a body_tags_order (its
	# divergent tags, as method symbols in publisher order); the head, image machinery, param lookup, title,
	# and the preview factory are shared. Lenient by design (previews whatever is present); strict publish
	# validation lives client-side + in the publisher.
	module Draftable
		extend ActiveSupport::Concern

		class_methods do
			# Normalized lookup tolerating string/symbol keys and ActionController::Parameters. A class method
			# so the factory can read params before instantiating; instances reach it through field.
			def value(params, key) = params[key.to_s].presence || params[key.to_sym].presence

			# Builds an unsaved kind-30402 Event preview from params, wrapped in the includer's presenter
			# class. Each Draft exposes it under its own public name (.listing / .open_request).
			def preview(params, pubkey:)
				attrs = { kind: Events::Kinds::CLASSIFIED, pubkey: pubkey.to_s, content: value(params, :description), tags: new(params).tags }
				presenter_class.new(Event.new(**attrs))
			end

			# Each Draft declares the presenter it wraps (Catalog::Listing / Requests::OpenRequest).
			def presenter_class = raise(NotImplementedError, "#{name} must define self.presenter_class")
		end

		def initialize(params)
			@params = params
		end

		# The kind-30402 tag set in publisher tag order: the shared head (d/title/t), then this includer's
		# body tags in the order it declares, then the image tags; nil entries are dropped. The head is
		# locked here so the marker can never drift ahead of the capability label / price (publisher order).
		def tags
			result = [ %w[d preview], [ "title", title ], [ "t", self.class.presenter_class.marker ] ]
			body_tags_order.each { |tag_name| result.push(send(tag_name)) }
			(result + image_tags).compact
		end

		private

		attr_reader :params

		# Each includer declares its divergent body tags, as method symbols in publisher order.
		def body_tags_order = raise(NotImplementedError, "#{self.class} must define #body_tags_order")

		def field(key) = self.class.value(params, key)

		def title = field(:title).presence || self.class.presenter_class::DEFAULT_TITLE

		# NIP-32 capability label, the discovery seam (brief §10.2): both sides emit the SAME canonical
		# namespace (the listing's) so a request and a listing that declare the same capability match.
		# OpenRequest has no namespace constant of its own; this literal is intentional, not a drift.
		def capability_tag
			cap = field(:capability)
			[ "l", cap, Catalog::Listing::CAPABILITY_NAMESPACE ] if cap.present?
		end

		# value + unit (hours/days) collapse to the microstandard suffix "24h" / "3d". The gating (manual
		# only, for a listing) stays in the caller; only the spelling is shared.
		def window_suffix(value, unit) = "#{value}#{unit == 'days' ? 'd' : 'h'}"

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
