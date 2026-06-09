# frozen_string_literal: true

module Requests
	# The poster's own conforming open request at a coordinate's d-tag, for editing. Scoped to the poster so
	# they can't edit another's, keyed on the stable d-tag (not the row id, which a re-publish recreates).
	# Raises NotFoundError when it is gone, superseded, not theirs, or no longer a conforming request (a
	# service listing shares kind 30402 and could occupy the same d). Mirrors Catalog::FindOwnListing.
	class FindOwnRequest < BaseService
		option :pubkey, type: Types::Strict::String
		option :d_tag, type: Types::Coercible::String

		def call
			event = Event.classified.find_by(pubkey:, d_tag:)
			request = event && OpenRequest.new(event)
			raise NotFoundError, "no editable request at #{d_tag}" unless request&.conforms?

			request
		end
	end
end
