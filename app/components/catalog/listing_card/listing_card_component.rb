# frozen_string_literal: true

module Catalog
	module ListingCard
		# A catalog listing as a horizontal list card: a constant thumbnail slot (so a listing with no
		# image lines up with one that has it), title + an optional fulfillment chip, capability + provider,
		# an optional one-line blurb, and the price. The whole row opens the buyer drawer.
		class ListingCardComponent < ApplicationComponent
			attr_reader :listing

			def initialize(listing:)
				@listing = listing
			end

			delegate :title, :description, :summary, :status, :price?, :price_amount,
							:price_currency, :price_suffix, :capability, :fulfillment, :provider_npub, :dom_id, :image,
							:search_text, :filter_mode, to: :listing

			def blurb = description.presence || summary
			def fulfillment_tone = fulfillment == "automated" ? :copper : :muted
			def fulfillment_label = fulfillment == "automated" ? "automated" : "human"

			# Sort keys for the client-side toolbar: integer sats (0 when unpriced) and the listing's unix ts.
			def price_value = price_amount.to_i
			def created_at = listing.event.nostr_created_at.to_i
		end
	end
end
