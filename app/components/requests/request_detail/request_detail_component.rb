# frozen_string_literal: true

module Requests
	module RequestDetail
		# The provider-facing detail shown in the slide-over drawer when someone opens an open request: the
		# need, the poster, the funded budget + windows, the funded-bounty/escrow model, and the (deferred)
		# claim action. The demand-side mirror of Catalog::ServiceDetail; reads from Requests::OpenRequest
		# and omits whatever a real event does not carry.
		class RequestDetailComponent < ApplicationComponent
			attr_reader :request, :viewer, :show_cta

			delegate :whole_sat_budget?, to: :request # the UI claim gate; shares the rule with Orders::Place

			# show_cta: false drops the claim action (the provider who already claimed reuses this same detail
			# in the messages drawer, where re-claiming makes no sense).
			def initialize(request:, viewer: nil, show_cta: true)
				@request = request
				@viewer = viewer
				@show_cta = show_cta
			end

			# The addressable coordinate the claim is placed against (kind:pubkey:d).
			def claim_coordinate = "#{Events::Kinds::CLASSIFIED}:#{request.event.pubkey}:#{request.identifier}"

			def default_mint = Orders::Policy.mint_allowlist.first

			# A signed-in non-author can claim an open, whole-sat request when a vetted mint is available.
			# Escrow locks whole sats, so non-sat / decimal / no-budget requests keep the inert CTA.
			def claimable?
				return false unless viewer && default_mint.present? && request.open?
				return false if viewer.pubkey == request.event.pubkey

				whole_sat_budget?
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
				"Claiming opens a funding window: the poster locks the budget to you in escrow (key-locked Cashu " \
					"with a timelock refund), and the delivery clock starts. It releases to you on delivery, or " \
					"refunds to the poster if you never deliver. Verify the locked budget before doing the work."
			end
		end
	end
end
