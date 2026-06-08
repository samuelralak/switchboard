# frozen_string_literal: true

require "bigdecimal"
require "digest"

module Requests
	# Presents a kind-30402 Event as an open request (a funded bounty, brief §10.2): the demand-side
	# inverse of a Catalog::Listing. Same NIP-99 kind, distinguished only by its own marker tag; it
	# reuses NIP-99's price tag for the budget and the shared capability namespace so a request and a
	# listing speak the same vocabulary (the discovery seam). No fulfillment or input schema: a request
	# states a need, it does not offer a service. Images (a cover) are supported, like a listing. Every
	# accessor tolerates absent tags.
	class OpenRequest
		BASE_MARKER = "switchboard-request"

		# The request marker, scoped by environment exactly like the listing marker, so development/test
		# requests never pollute the production board (production is the bare marker; other envs suffixed).
		# One source of truth, used by conforms?, the publisher, mutual exclusion, and Requests::Search.
		def self.marker
			Rails.env.production? ? BASE_MARKER : "#{BASE_MARKER}-#{Rails.env}"
		end

		attr_reader :event

		def initialize(event)
			@event = event
		end

		def title = event.tag("title").presence || "Untitled request"
		def summary = event.tag("summary").presence || description.truncate(140)
		def description = event.content.to_s
		def status = event.tag("status").presence || "active"
		# Live on the board? The lifecycle (open -> claimed -> expired) is carried in the status tag; only
		# "active" (open, unclaimed) shows publicly. Claim binding + the funded states land with escrow.
		def open? = status == "active"
		def published_at = event.tag("published_at")
		def identifier = event.tag("d").to_s
		def conforms? = event.tag_values("t").include?(self.class.marker)

		# Capability shares the listing namespace (brief §10.2 discovery): a provider whose listing declares
		# capability X can be matched to a request tagged X. Read-lenient, like Catalog::Listing#capability.
		def capability
			event.tags.find do |t|
				t.is_a?(Array) && t[0] == "l" && t[2].to_s.end_with?(Catalog::Listing::CAPABILITY_L)
			end&.dig(1)
		end

		# The funded budget, reusing NIP-99's price tag ["price", amount, currency]. A bounty is a single
		# fixed amount (brief §10.2: one budget, no bidding), so there is no recurring frequency.
		def budget_amount
			amount = budget_tag[1].to_s
			return unless amount.match?(/\A\d+(\.\d+)?\z/)

			amount.include?(".") ? BigDecimal(amount) : amount.to_i
		end

		def budget_currency = budget_tag[2].presence || "sat"
		def budget? = budget_amount.present?

		# Escrow locks whole sats, so only a fixed positive whole-sat budget is claimable. One source of truth
		# for the UI claim gate (Requests::RequestDetail) and the server enforcement (Orders::Place).
		def whole_sat_budget? = budget_currency == "sat" && budget_amount.is_a?(Integer) && budget_amount.positive?

		# How long a provider has to claim before the budget auto-refunds (brief §10.2 claim window),
		# and the post-claim turnaround the consumer asks for. Microstandard form e.g. "7d" / "48h".
		def claim_window = event.tag("claim_window")
		def delivery_window = event.tag("delivery_window")

		# Cover image (first image tag), restricted to http(s): a foreign request could carry a
		# javascript:/data: url, and this flows into an <img src>. Defense-in-depth on top of ERB escaping.
		def image = http_url(event.tag("image"))
		# All request images (NIP-99 image tags, http(s) only); the first is the cover.
		def images = event.tags.select { |t| t.is_a?(Array) && t[0] == "image" }.filter_map { |t| http_url(t[1]) }

		# NIP-92 imeta metadata for an image url: { url:, m:, x:, dim: } (present keys only), or {} when none.
		def image_meta(url)
			tag = imeta_tag(url)
			return {} unless tag

			tag.drop(1).each_with_object({}) do |pair, meta|
				key, value = pair.to_s.split(" ", 2)
				meta[key.to_sym] = value if key.present? && value.present?
			end
		end

		# The consumer who posted the request (the bounty funder), as an npub.
		def poster_npub
			Nostr::Bech32.npub_encode(event.pubkey)
		rescue StandardError
			event.pubkey
		end

		# DOM id derived from the addressable coordinate, stable across re-publishes.
		def dom_id = "request_#{Digest::SHA256.hexdigest(coordinate)[0, 16]}"

		# Lowercased haystack for the client-side board filter.
		def search_text = [ title, description, capability ].compact.join(" ").downcase
		def matches?(query) = search_text.include?(query.to_s.downcase)

		private

		def coordinate = "#{event.kind}:#{event.pubkey}:#{event.d_tag}"
		def budget_tag = event.tags.find { |t| t.is_a?(Array) && t[0] == "price" } || []

		# A url only if it is http(s); otherwise nil (keeps javascript:/data: urls out of <img src>).
		def http_url(url) = url.to_s.match?(%r{\Ahttps?://}i) ? url : nil

		def imeta_tag(url)
			event.tags.find { |t| t.is_a?(Array) && t[0] == "imeta" && t.include?("url #{url}") }
		end
	end
end
