# frozen_string_literal: true

module Requests
	module RequestDetail
		# The provider-facing detail shown in the slide-over drawer when someone opens an open request: the
		# need, the poster, the funded budget + windows, the funded-bounty/escrow model, and the (deferred)
		# claim action. The demand-side mirror of Catalog::ServiceDetail; reads from Requests::OpenRequest
		# and omits whatever a real event does not carry.
		class RequestDetailComponent < ApplicationComponent
			attr_reader :request

			def initialize(request:)
				@request = request
			end

			# The consumer's asked-for turnaround once a provider claims; nil when none is declared.
			def delivery_label
				request.delivery_window.presence && "deliver in #{request.delivery_window}"
			end

			# How long the request stays open for a provider to claim; nil when none is declared.
			def claim_label
				request.claim_window.presence && "claim within #{request.claim_window}"
			end

			# The funded-bounty guarantee (brief §10.2). Posting deposits the budget into escrow up front and
			# pays a separate non-refundable posting fee; the deposit binds to the provider who claims and
			# releases on delivery, or refunds if it goes unclaimed/undelivered. Currently informational: the
			# escrow + fee mechanics land with the payments work, so a request is publish-and-browse for now.
			def funding_explainer
				"The budget is deposited into escrow when the request is posted (locked to the poster's keys " \
					"with a timelock refund), so a claiming provider sees committed sats. It releases on delivery, " \
					"or refunds if the request goes unclaimed or undelivered. A small non-refundable posting fee " \
					"funds the platform. Escrow and the fee are coming with payments."
			end
		end
	end
end
