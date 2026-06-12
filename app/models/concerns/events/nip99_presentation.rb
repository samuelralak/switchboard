# frozen_string_literal: true

require "bigdecimal"
require "digest"

module Events
	# Shared presenter behavior for a kind-30402 NIP-99 classified event: the fields a Catalog::Listing and a
	# Requests::OpenRequest read the same way (title/summary/status/images/capability, the price-tag amount,
	# the coordinate-derived dom id, free-text search). Each including class declares BASE_MARKER,
	# DEFAULT_TITLE, and DOM_PREFIX, then layers on its own vocabulary (price_* vs budget_*, fulfillment vs
	# claim_window). Every accessor tolerates absent / malformed tags.
	module Nip99Presentation
		extend ActiveSupport::Concern

		# NIP-32 capability label key: ["l", value, "<ns>.capability"]. Shared so a listing and a request that
		# declare the same capability match (the discovery seam, brief §10.2). The reader stays lenient (any
		# namespace ending in this key); the publisher emits the one canonical namespace per side.
		CAPABILITY_L = "capability"

		included do
			attr_reader :event
		end

		class_methods do
			# The marker tag, scoped by environment so non-production events never pollute production discovery
			# (production is the bare marker; other envs suffixed). One source of truth for conforms?, the
			# publisher, and search.
			def marker
				Rails.env.production? ? self::BASE_MARKER : "#{self::BASE_MARKER}-#{Rails.env}"
			end
		end

		def initialize(event)
			@event = event
		end

		def title = event.tag("title").presence || self.class::DEFAULT_TITLE
		def summary = event.tag("summary").presence || description.truncate(140)

		# NIP-99 content is the human-readable (Markdown) description. Some upstream sources (e.g. Conduit) put
		# the serialized event JSON in content instead; never render that raw -- fall back to the summary tag
		# (clean text) when the content reads as a JSON blob.
		def description
			content = event.content.to_s
			json_blob?(content) ? event.tag("summary").to_s : content
		end
		def status = event.tag("status").presence || "active"
		# Original publish time (NIP-99); carried through edits so it is not reset on re-publish.
		def published_at = event.tag("published_at")
		# The addressable `d` identifier (stable id across re-publishes/edits).
		def identifier = event.tag("d").to_s
		def conforms? = event.tag_values("t").include?(self.class.marker)

		# Microstandard capability label, read-lenient (any namespace ending in CAPABILITY_L).
		def capability
			event.tags.find { |t| t.is_a?(Array) && t[0] == "l" && t[2].to_s.end_with?(CAPABILITY_L) }&.dig(1)
		end

		# Cover image (first image tag), restricted to http(s): a foreign event could carry a javascript:/data:
		# url, and this flows into an <img src>. Defense-in-depth on top of ERB escaping + the CSP img-src.
		def image = http_url(event.tag("image"))
		# All images (NIP-99 image tags, http(s) only); the first is the cover.
		def images = event.tags.select { |t| t.is_a?(Array) && t[0] == "image" }.filter_map { |t| http_url(t[1]) }

		# NIP-92 imeta metadata for an image url: { url:, m:, x:, dim:, blurhash:, alt: } (present keys only),
		# or {} when there is no matching imeta tag.
		def image_meta(url)
			tag = imeta_tag(url)
			return {} unless tag

			tag.drop(1).each_with_object({}) do |pair, meta|
				key, value = pair.to_s.split(" ", 2)
				meta[key.to_sym] = value if key.present? && value.present?
			end
		end

		# The event author as an npub; falls back to the raw hex if encoding fails.
		def author_npub
			Nostr::Bech32.npub_encode(event.pubkey)
		rescue StandardError
			event.pubkey
		end

		# The addressable coordinate (kind:pubkey:d); what an escrow order is placed against, and the seed for
		# the dom id. Stable across re-publishes.
		def coordinate = "#{event.kind}:#{event.pubkey}:#{event.d_tag}"

		# DOM id derived from the coordinate, stable across re-publishes.
		def dom_id = "#{self.class::DOM_PREFIX}_#{Digest::SHA256.hexdigest(coordinate)[0, 16]}"

		# Lowercased haystack for the client-side filter, and the free-text match against it.
		def search_text = [ title, description, capability ].compact.join(" ").downcase
		def matches?(query) = search_text.include?(query.to_s.downcase)

		private

		# The NIP-99 price tag ["price", amount, currency, frequency?]; the request reuses it for its budget.
		def price_tag = event.tags.find { |t| t.is_a?(Array) && t[0] == "price" } || []

		# NIP-99 amount string -> Integer (whole) or BigDecimal (fractional), or nil when absent / non-numeric.
		# Integer() would mangle hex / underscore forms, so a plain decimal must match first.
		def parse_amount(raw)
			amount = raw.to_s
			return unless amount.match?(/\A\d+(\.\d+)?\z/)

			amount.include?(".") ? BigDecimal(amount) : amount.to_i
		end

		# Escrow locks whole sats, so only a fixed positive whole-sat amount is orderable. One source of truth
		# for the listing price / request budget UI gates and the server enforcement (Orders::Place), so the
		# gate and the enforcement can never drift.
		def whole_sat?(amount, currency) = currency == "sat" && amount.is_a?(Integer) && amount.positive?

		# A url only if it is http(s); otherwise nil (keeps javascript:/data: urls out of <img src>).
		def http_url(url) = url.to_s.match?(%r{\Ahttps?://}i) ? url : nil

		# Heuristic: does the content read as serialized JSON (an object, or an array whose first element is a
		# string/array/object) rather than Markdown prose? Catches a serialized event or tag set without
		# clobbering a Markdown link, which starts "[text](...".
		def json_blob?(text)
			stripped = text.lstrip

			stripped.start_with?("{") || stripped.match?(/\A\[\s*["\[{]/)
		end

		def imeta_tag(url)
			event.tags.find { |t| t.is_a?(Array) && t[0] == "imeta" && t.include?("url #{url}") }
		end
	end
end
