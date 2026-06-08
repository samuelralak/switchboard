# frozen_string_literal: true

module Orders
	module Actions
		# The order's action area, branching by state and the viewer's role: the consumer funds (awaiting)
		# then releases or refunds (funded); the provider verifies then redeems (funded). Each panel wires the
		# browser controller (funding / settlement) that does the Cashu work. render? hides it for everyone else
		# and in terminal states.
		class ActionsComponent < ApplicationComponent
			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			def render? = fund? || release? || settle?

			def fund? = awaiting? && consumer?
			def release? = funded? && consumer?
			# Provider can deliver the result AND verify/redeem once funded (both live in the settle? branch).
			def settle? = funded? && provider?

			def relays_json = NostrClient.configuration.relays.to_json
			# Gift-wraps (the delivered result) use the NIP-17 inbox relay set, matching the consumer result panel.
			def dm_relays_json = NostrClient.configuration.dm_relays.to_json
			def locktime_seconds = Orders::Policy.default_locktime_seconds

			private

			def awaiting? = order.current_state == Orders::States::AWAITING_FUNDING
			def funded? = order.current_state == Orders::States::FUNDED
			def consumer? = viewer.pubkey == order.consumer_pubkey
			def provider? = viewer.pubkey == order.provider_pubkey
		end
	end
end
