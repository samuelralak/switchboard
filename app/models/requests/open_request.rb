# frozen_string_literal: true

module Requests
	# Presents a kind-30402 Event as an open request (a funded bounty, brief §10.2): the demand-side inverse
	# of a Catalog::Listing. Same NIP-99 kind, distinguished only by its own marker tag; it reuses NIP-99's
	# price tag for the budget and shares the capability namespace so a request and a listing speak the same
	# vocabulary (the discovery seam). Shared NIP-99 reading lives in Events::Nip99Presentation; this adds the
	# request's own vocabulary: the funded budget and the claim/delivery windows. No fulfillment or input
	# schema (a request states a need, it does not offer a service). Every accessor tolerates absent tags.
	class OpenRequest
		include Events::Nip99Presentation
		include Attestation::Attestable

		BASE_MARKER   = "switchboard-request"
		DEFAULT_TITLE = "Untitled request"
		DOM_PREFIX    = "request"

		# Live on the board? The lifecycle (open -> claimed -> expired) is carried in the status tag; only
		# "active" (open, unclaimed) shows publicly. Claim binding + the funded states land with escrow.
		def open? = status == "active"

		# The consumer who posted the request (the bounty funder), as an npub.
		def poster_npub = author_npub

		# The funded budget, reusing NIP-99's price tag ["price", amount, currency]. A bounty is a single fixed
		# amount (brief §10.2: one budget, no bidding), so there is no recurring frequency.
		def budget_amount = parse_amount(price_tag[1])
		def budget_currency = price_tag[2].presence || "sat"
		def budget? = budget_amount.present?

		# Escrow locks whole sats, so only a fixed positive whole-sat budget is claimable. The UI claim gate
		# (Requests::RequestDetail) and the server enforcement (Orders::Place) read this one rule.
		def whole_sat_budget? = whole_sat?(budget_amount, budget_currency)

		# How long a provider has to claim before the budget auto-refunds (brief §10.2 claim window), and the
		# post-claim turnaround the consumer asks for. Microstandard form e.g. "7d" / "48h".
		def claim_window = event.tag("claim_window")
		def delivery_window = event.tag("delivery_window")

		# The escrow tier the poster opted into when authoring. A catalog buyer picks the tier at order time,
		# but a request is funded by its poster, so the choice rides on the event and the claiming provider
		# cannot change it (Orders::Place stamps this onto the claim order). Clamps an absent/unrecognized tag
		# to tier-1 (self-custodial), the safe default.
		def escrow_tier
			tier = event.tag("escrow_tier")

			Orders::Tiers::ALL.include?(tier) ? tier : Orders::Tiers::TIER1_HTLC
		end
	end
end
