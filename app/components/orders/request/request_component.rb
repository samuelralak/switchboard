# frozen_string_literal: true

module Orders
	module Request
		# The consumer's encrypted request panel on the order page: the filled service inputs + an optional
		# note, sealed to the provider over NIP-17 (the order_request controller does the gift-wrap). Catalog
		# orders only -- a claimed request is already public on relays. Shown to the consumer while the order
		# is active; the runtime never sees the content.
		class RequestComponent < ApplicationComponent
			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			def render? = consumer? && catalog_order? && !order.terminal?

			def fields = listing&.input_schema || []
			def relays_json = NostrClient.configuration.dm_relays.to_json

			private

			def consumer? = viewer&.pubkey == order.consumer_pubkey
			def catalog_order? = order.entry_point == Orders::EntryPoints::CATALOG_ORDER

			# The listing the order targets, when ingested locally (its input_schema is the request form), via the
			# shared resolver -- no DB access from the component. A missing listing still allows a free-form note.
			def listing
				@listing = defined?(@listing) ? @listing : Orders::ServiceFor.call(order:)
			end
		end
	end
end
