# frozen_string_literal: true

module Orders
	# Order lifecycle states and the allowed transitions between them.
	module States
		AWAITING_FUNDING = "awaiting_funding"
		FUNDED           = "funded"
		RELEASED         = "released"
		REFUNDED         = "refunded"
		EXPIRED          = "expired"

		ALL         = [ AWAITING_FUNDING, FUNDED, RELEASED, REFUNDED, EXPIRED ].freeze
		ACTIVE      = [ AWAITING_FUNDING, FUNDED ].freeze
		TERMINAL    = [ RELEASED, REFUNDED, EXPIRED ].freeze
		SETTLEMENTS = [ RELEASED, REFUNDED ].freeze

		# from => allowed to-states
		TRANSITIONS = {
			AWAITING_FUNDING => [ FUNDED, EXPIRED ],
			FUNDED => [ RELEASED, REFUNDED ]
		}.freeze

		module_function

		def terminal?(state) = TERMINAL.include?(state)
		def settlement?(state) = SETTLEMENTS.include?(state)
		def allowed?(from, to) = TRANSITIONS.fetch(from, []).include?(to)
	end
end
