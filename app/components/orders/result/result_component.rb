# frozen_string_literal: true

module Orders
	module Result
		# The delivered-result panel on the order page. Two viewers, one component:
		#   - the CONSUMER sees the provider's finished work, decrypted from the result envelope, so they can
		#     verify it before releasing the escrow;
		#   - the PROVIDER sees their OWN delivery, decrypted from the provider self-copy the result envelope
		#     keeps, once they have delivered -- so they can confirm what they sent (the note + inputs).
		# The order_result controller does the decryption client-side with the VIEWER's signer (own = viewer);
		# the runtime never sees the result. Shown from funded through released; the trust anchor is always the
		# order's provider (a result is only rendered when its envelope author is that provider).
		class ResultComponent < ApplicationComponent
			SHOWN_STATES = [ Orders::States::FUNDED, Orders::States::RELEASED ].freeze

			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			# The consumer always gets the panel (a result may have arrived); the provider gets it only once they
			# have delivered, so their self-copy exists to decrypt.
			def render?
				order.current_state.in?(SHOWN_STATES) && (consumer? || delivered_by_provider?)
			end

			def heading
				provider? ? "your delivery" : "data out · delivered result"
			end

			def icon
				provider? ? "sent" : "download-01"
			end

			def relays_json
				NostrClient.configuration.dm_relays.to_json
			end

			private

			def consumer?
				viewer&.pubkey == order.consumer_pubkey
			end

			def provider?
				viewer&.pubkey == order.provider_pubkey
			end

			def delivered_by_provider?
				provider? && order.delivery.present?
			end
		end
	end
end
