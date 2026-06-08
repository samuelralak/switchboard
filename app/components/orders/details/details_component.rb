# frozen_string_literal: true

module Orders
	module Details
		# The order summary: the two parties, the mint, and (while awaiting) the funding deadline.
		class DetailsComponent < ApplicationComponent
			attr_reader :order

			def initialize(order:)
				@order = order
			end

			def awaiting? = order.current_state == Orders::States::AWAITING_FUNDING
			def npub(pubkey) = helpers.order_npub(pubkey)
		end
	end
end
