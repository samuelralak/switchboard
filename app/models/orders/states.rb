# frozen_string_literal: true

module Orders
	# Order lifecycle states and the allowed transitions between them.
	module States
		AWAITING_FUNDING = "awaiting_funding"
		FUNDED           = "funded"
		DISPUTED         = "disputed"
		RELEASED         = "released"
		REFUNDED         = "refunded"
		EXPIRED          = "expired"

		ALL         = [ AWAITING_FUNDING, FUNDED, DISPUTED, RELEASED, REFUNDED, EXPIRED ].freeze
		ACTIVE      = [ AWAITING_FUNDING, FUNDED, DISPUTED ].freeze
		TERMINAL    = [ RELEASED, REFUNDED, EXPIRED ].freeze
		SETTLEMENTS = [ RELEASED, REFUNDED ].freeze
		# Orders whose proofs may have moved at the mint and need reconciling: funded, plus a disputed order
		# the arbiter ruled on. The reconcile sweep + Settlement scan this set (Tier-2 Slice 3).
		SETTLEABLE  = [ FUNDED, DISPUTED ].freeze

		# from => allowed to-states
		TRANSITIONS = {
			AWAITING_FUNDING => [ FUNDED, EXPIRED ],
			FUNDED => [ RELEASED, REFUNDED, DISPUTED ],
			DISPUTED => [ RELEASED, REFUNDED ]
		}.freeze

		module_function

		def terminal?(state) = TERMINAL.include?(state)
		def settlement?(state) = SETTLEMENTS.include?(state)
		def allowed?(from, to) = TRANSITIONS.fetch(from, []).include?(to)
	end
end
