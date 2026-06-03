# frozen_string_literal: true

require "dry-types"

module NostrClient
	# dry-types definitions for the relay client boundary. Referenced from
	# Configuration (relay list) and Connection (url, lifecycle state).
	module Types
		include Dry.Types()

		# A relay endpoint: a ws:// or wss:// WebSocket URL.
		RelayUrl = Strict::String.constrained(format: %r{\Awss?://}i)

		# The set of relays the client connects to.
		Relays = Array.of(RelayUrl)

		# Connection lifecycle states (NIP-01 client).
		ConnectionState = Strict::Symbol.enum(:disconnected, :connecting, :connected, :closing)

		# A NIP-01 subscription identifier.
		SubscriptionId = Strict::String

		# Anything that responds to #call (a proc or a Method).
		Callable = Interface(:call)
	end
end
