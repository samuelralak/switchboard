# frozen_string_literal: true

module Orders
	# The on-relay service an order targets, resolved from its listing_coordinate: a Catalog::Listing for a
	# catalog order, a Requests::OpenRequest for a claimed request, or nil if the event is not ingested
	# locally. One resolver for both entry points, shared by the order ledger and the messages inbox.
	class ServiceFor < BaseService
		option :order

		def call
			event = Event.by_coordinate(order.listing_coordinate)
			return unless event

			request? ? Requests::OpenRequest.new(event) : Catalog::Listing.new(event)
		end

		private

		def request? = order.entry_point == EntryPoints::REQUEST_CLAIM
	end
end
