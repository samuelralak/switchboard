# frozen_string_literal: true

module Messages
	module ServiceDetail
		# The service/listing detail shown in the right slide-over drawer: mode, description,
		# price, the escrow-every-job explainer, the input schema (label/type/required), and
		# the kind-30402 conformance line. Mirrors the prototype's viewService, reframed for a
		# provider viewing their own listing (no buyer CTA, no self-referential track record).
		class ServiceDetailComponent < ApplicationComponent
			# The service-listing microstandard marker (brief §7.1). Placeholder namespace.
			MARKER = "switchboard-service"

			# The dialog id the trigger button and the drawer share (one service shows at a time).
			DRAWER_ID = "service-drawer"

			attr_reader :conversation

			def initialize(conversation:)
				@conversation = conversation
			end

			def escrow_explainer
				if conversation.automated?
					"Automated escrow. Funds lock as a Lightning hold invoice, released to you on a valid " \
						"response and auto-cancelled if the endpoint times out. Genuinely trustless for fast work."
				else
					"Manual escrow. The client's funds lock as key-locked Cashu (NUT-11 P2PK), released to you " \
						"on approval, with a timelock refund to them if you miss the #{conversation.span}. Locked " \
						"to keys, never held by us."
				end
			end
		end
	end
end
