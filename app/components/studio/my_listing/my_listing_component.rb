# frozen_string_literal: true

module Studio
	module MyListing
		# One row in the studio's My-listings: cover, title, status, price + mode + capability, with an Edit
		# link and an Unpublish/Re-publish toggle. The toggle re-signs the existing event with the status
		# tag flipped (preserving all data); `payload` carries that event to the my_listings controller.
		class MyListingComponent < ApplicationComponent
			attr_reader :listing

			def initialize(listing:)
				@listing = listing
			end

			delegate :title, :status, :active?, :image, :capability, :identifier, to: :listing
			delegate :price?, :price_amount, :price_currency, :price_suffix, :fulfillment, to: :listing

			def fulfillment_label = fulfillment == "automated" ? "automated" : "human"
			def next_status = active? ? "inactive" : "active"
			def toggle_label = active? ? "Unpublish" : "Re-publish"
			def status_tone = active? ? "text-lamp-settled" : "text-ink-faint"

			# The event the status toggle re-signs (kind + content + tags + created_at, so the re-sign can
			# supersede with a monotonic created_at), as JSON for the data param.
			def payload
				{ kind: listing.event.kind, content: listing.event.content, tags: listing.event.tags,
					created_at: listing.event.nostr_created_at&.to_i }.to_json
			end
		end
	end
end
