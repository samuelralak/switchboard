# frozen_string_literal: true

module Requests
	# Open requests on the board: kind-30402 events carrying the request marker, optionally narrowed by a
	# free-text substring over the newest `limit`. The demand-side mirror of Catalog::Search.
	class Search < BaseService
		option :query, type: Types::Strict::String.optional, default: -> { }
		option :pubkey, type: Types::Strict::String.optional, default: -> { } # set = one poster's own (My requests)
		option :limit, type: Types::Coercible::Integer, default: -> { 120 }
		option :shown, type: Types::Coercible::Integer, default: -> { 60 }

		def call
			requests = board_scope.recent.limit(limit).map { |event| OpenRequest.new(event) }
			requests = requests.select(&:open?) # drops claimed/expired (non-"active") once those states exist
			requests = requests.select { |request| request.matches?(query) } if query.present?
			requests.first(shown)
		end

		private

		# Request-marked classified events the poster has NOT withdrawn (status=inactive), filtered in SQL so
		# the `limit` applies to visible rows. Both filters use the tags GIN index. The marker include is what
		# keeps service listings off the board (and, symmetrically, requests out of the catalog).
		def board_scope
			scope = Event.classified.active.not_from_flagged.with_tag("t", OpenRequest.marker).not_unpublished
			pubkey.present? ? scope.by_author(pubkey) : scope
		end
	end
end
