# frozen_string_literal: true

require "dry/configurable"

module NostrClient
	# Typed dry-configurable settings for the relay list and reconnection tuning.
	#
	#   NostrClient.configure { |c| c.relays = ["wss://relay.damus.io"] }
	#   NostrClient.configuration.relays # => ["wss://relay.damus.io"]
	class Configuration
		extend Dry::Configurable

		setting :relays, default: [].freeze, constructor: Types::Relays
		setting :max_reconnect_attempts, default: 10, constructor: Types::Coercible::Integer
		setting :reconnect_delay_seconds, default: 2, constructor: Types::Coercible::Integer
	end
end
