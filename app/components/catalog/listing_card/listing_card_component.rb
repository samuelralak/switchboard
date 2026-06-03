# frozen_string_literal: true

module Catalog
	module ListingCard
		# A catalog service tile: title and price, an optional fulfillment-mode chip,
		# a two-line description, and the provider identity.
		class ListingCardComponent < ApplicationComponent
			attr_reader :listing

			def initialize(listing:)
				@listing = listing
			end

			delegate :title, :description, :summary, :status, :price?, :price_amount,
							:price_currency, :fulfillment, :provider_npub, :dom_id,
							:search_text, :filter_mode, to: :listing

			def blurb = description.presence || summary
			def fulfillment_tone = fulfillment == "automated" ? :copper : :muted
			def fulfillment_label = fulfillment == "automated" ? "automated" : "human"
		end
	end
end
