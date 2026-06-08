# frozen_string_literal: true

module Catalog
	# The provider's own conforming listing at a coordinate's d-tag, for editing. Scoped to the provider so
	# they can't edit another's, keyed on the stable d-tag (not the row id, which a re-publish recreates).
	# Raises NotFoundError when it is gone, superseded, not theirs, or no longer a conforming listing (an open
	# request shares kind 30402 and could occupy the same d).
	class FindOwnListing < BaseService
		option :pubkey, type: Types::Strict::String
		option :d_tag, type: Types::Coercible::String

		def call
			event = Event.classified.find_by(pubkey:, d_tag:)
			listing = event && Listing.new(event)
			raise NotFoundError, "no editable listing at #{d_tag}" unless listing&.conforms?

			listing
		end
	end
end
