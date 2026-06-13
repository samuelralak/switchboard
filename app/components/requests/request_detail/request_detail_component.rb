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
			def claim_coordinate = request.coordinate

			# A signed-in non-author can claim an open, whole-sat request when a vetted mint is available.
			# Escrow locks whole sats, so non-sat / decimal / no-budget requests keep the inert CTA.
			def claimable?
				return false unless viewer && Orders::Policy.default_mint.present? && request.open?
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

			# The funded-bounty guarantee (brief §10.2), fund-at-claim: a request posts UNFUNDED (a declaration +
			# a non-refundable posting fee); when a provider claims, the poster funds by locking the budget to
			# that provider, and it releases on delivery or refunds if undelivered / the claim lapses. The
			# at-claim escrow is live via the order flow; only the posting fee lands later with the payments work.
			def funding_explainer
				"Claiming opens a funding window: the poster locks the budget to you in escrow (key-locked Cashu " \
					"with a timelock refund), and the delivery clock starts. It releases to you on delivery, or " \
					"refunds to the poster if you never deliver. The budget sits at a Cashu mint while locked, so a " \
					"mint outage can stall your redemption or the refund. Verify the locked budget before doing the work."
			end

			# Extra line shown only on a mediated request: how a dispute resolves through the platform arbiter,
			# so the claiming provider knows the trust model before taking the work. nil for standard escrow.
			def arbiter_note
				return unless mediated_escrow?

				"If you and the poster disagree, either side can escalate to the platform arbiter, who can co-sign " \
					"the release to one party but can never move the funds alone."
			end

			# The poster opted into arbiter-mediated escrow (vs the self-custodial default), so the claiming
			# provider sees how a dispute would resolve before taking the work.
			def mediated_escrow? = request.escrow_tier == Orders::Tiers::TIER2_ARBITER

			# The escrow type, surfaced as a small pill beside the funded-bounty label.
			def escrow_label = mediated_escrow? ? "mediated escrow" : "standard escrow"
		end
	end
end
