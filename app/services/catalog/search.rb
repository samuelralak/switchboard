# frozen_string_literal: true

module Catalog
	# Recent active catalog listings, optionally narrowed by a free-text substring over
	# the newest `limit`. Deliberately simple: a placeholder until the router lands.
	class Search < BaseService
		option :query, type: Types::Strict::String.optional, default: -> { }
		option :limit, type: Types::Coercible::Integer, default: -> { 120 }
		option :shown, type: Types::Coercible::Integer, default: -> { 60 }

		def call
			listings = Event.classified.active.recent.limit(limit).map { |event| Listing.new(event) }
			listings = listings.select { |listing| listing.matches?(query) } if query.present?
			listings.first(shown)
		end
	end
end
