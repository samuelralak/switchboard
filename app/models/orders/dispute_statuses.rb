# frozen_string_literal: true

module Orders
	# The lifecycle of a Tier-2 dispute: open until the platform arbiter rules it for one party.
	module DisputeStatuses
		OPEN               = "open"
		RULED_FOR_PROVIDER = "ruled_for_provider"
		RULED_FOR_CONSUMER = "ruled_for_consumer"

		ALL   = [ OPEN, RULED_FOR_PROVIDER, RULED_FOR_CONSUMER ].freeze
		RULED = [ RULED_FOR_PROVIDER, RULED_FOR_CONSUMER ].freeze
	end
end
