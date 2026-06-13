# frozen_string_literal: true

module Orders
	# The on-relay service an order targets, resolved from its listing_coordinate: a Catalog::Listing for a
	# catalog order, a Requests::OpenRequest for a claimed request, or nil if the event is not ingested
	# locally. One resolver for both entry points, shared by the order ledger and the messages inbox.
	class ServiceFor < BaseService
		option :order

		def call
			event = Event.by_coordinate(order.listing_coordinate)
			event && self.class.wrap(order, event)
		end

		# Resolve many orders' services in ONE Event query: an {order.id => service} map (nil per order when its
		# coordinate is not ingested locally). The ledger + inbox use this instead of a by_coordinate per order.
		def self.map_for(orders)
			events = events_by_coordinate(orders.map(&:listing_coordinate))

			orders.to_h do |order|
				event = events[order.listing_coordinate]
				[ order.id, event && wrap(order, event) ]
			end
		end

		# The classified events for a set of coordinates, in ONE query, keyed by "kind:pubkey:d_tag".
		def self.events_by_coordinate(coordinates)
			parsed = coordinates.map { |coordinate| coordinate.to_s.split(":", 3) }
			Event.where(
				kind: parsed.map { |kind, _, _| kind.to_i }.uniq,
				pubkey: parsed.map { |_, pubkey, _| pubkey }.uniq,
				d_tag: parsed.map { |_, _, d_tag| d_tag.to_s }.uniq
			).index_by(&:coordinate)
		end

		# Wrap an order's resolved event as the presenter for its entry point.
		def self.wrap(order, event)
			if order.entry_point == EntryPoints::REQUEST_CLAIM
				Requests::OpenRequest.new(event)
			else
				Catalog::Listing.new(event)
			end
		end
	end
end
