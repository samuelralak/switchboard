# frozen_string_literal: true

module Orders
	# Escrow tier identifiers.
	module Tiers
		TIER1_HTLC    = "tier1_htlc"
		TIER2_ARBITER = "tier2_arbiter"

		ALL = [ TIER1_HTLC, TIER2_ARBITER ].freeze
	end
end
