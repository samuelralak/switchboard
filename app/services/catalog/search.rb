# frozen_string_literal: true

module Catalog
	# Recent active catalog listings, optionally narrowed by a free-text substring over
	# the newest `limit`. Deliberately simple: a placeholder until the router lands.
	class Search < BaseService
		option :query, type: Types::Strict::String.optional, default: -> { }
		option :limit, type: Types::Coercible::Integer, default: -> { 120 }
		option :shown, type: Types::Coercible::Integer, default: -> { 60 }

		def call
			listings = catalog_scope.recent.limit(limit).map { |event| Listing.new(event) }
			listings = listings.select(&:active?) # also drops other non-"active" statuses (e.g. NIP-99 "sold")
			listings = listings.select { |listing| listing.matches?(query) } if query.present?
			listings.first(shown)
		end

		private

		# Active (NIP-40 not-expired) classified listings the author has NOT unpublished (status=inactive),
		# filtered in SQL so the `limit` applies to visible rows (not starved by a backlog of unpublished
		# ones). jsonb @> uses the tags GIN index. Note: Event.active is NIP-40 expiry, distinct from this.
		# Open requests share kind 30402 and are excluded by their marker, so the demand board never leaks
		# into the supply catalog (Requests::Search applies the symmetric include).
		def catalog_scope
			Event.classified.active.not_unpublished.without_tag("t", Requests::OpenRequest.marker)
		end
	end
end
