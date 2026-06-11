# frozen_string_literal: true

module Orders
	module IncomingRequest
		# The consumer's encrypted request, shown to the PROVIDER on the order page so they can see what to
		# deliver without leaving for a separate inbox. The content is sealed to the provider over NIP-17 and
		# decrypted client-side by the `messages` controller (the runtime never sees it). Catalog orders only --
		# a claimed request is already public on relays. The provider-side mirror of Orders::Request (which is
		# the consumer's send form); folds the request view that used to live only in Messages::Thread into the
		# order detail.
		class IncomingRequestComponent < ApplicationComponent
			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			def render?
				provider? && catalog_order? && !order.terminal?
			end

			def dm_relays_json
				NostrClient.configuration.dm_relays.to_json
			end

			private

			def provider?
				viewer&.pubkey == order.provider_pubkey
			end

			def catalog_order?
				order.entry_point == Orders::EntryPoints::CATALOG_ORDER
			end
		end
	end
end
