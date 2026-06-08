# frozen_string_literal: true

module Orders
	module Result
		# The consumer's "data out · delivered result" panel on the order page: the provider's finished work,
		# decrypted client-side by the order_result controller (the runtime never sees it) and shown so the
		# consumer can verify before releasing. Visible to the consumer once funded (a result may have arrived)
		# through released; a result envelope may not exist yet, in which case the panel says so.
		class ResultComponent < ApplicationComponent
			SHOWN_STATES = [ Orders::States::FUNDED, Orders::States::RELEASED ].freeze

			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			def render? = consumer? && order.current_state.in?(SHOWN_STATES)

			def relays_json = NostrClient.configuration.dm_relays.to_json

			private

			def consumer? = viewer&.pubkey == order.consumer_pubkey
		end
	end
end
