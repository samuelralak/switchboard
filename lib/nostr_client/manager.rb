# frozen_string_literal: true

require "singleton"

module NostrClient
	# Holds the relay connections and dispatches inbound NIP-01 frames by type.
	# EVENT/EOSE reach the consumer hooks, CLOSED retires the subscription, and
	# NOTICE/OK/AUTH are logged. Active subscriptions are applied to connections added later.
	class Manager
		include Singleton

		def initialize
			@connections = {}
			@subscriptions = {} # subscription_id => filters
			@mutex = Mutex.new
			@on_event = nil
			@on_eose = nil
		end

		# Registers consumer hooks:
		#   on_event { |connection, subscription_id, event| ... }
		#   on_eose  { |connection, subscription_id| ... }
		def on_event(&block) = @on_event = block
		def on_eose(&block) = @on_eose = block

		# Adds a relay connection at +url+ and subscribes it to all active subscriptions.
		def add_connection(url)
			connection = Connection.new(url:, on_message: method(:route))
			@mutex.synchronize do
				@connections[url] = connection
				@subscriptions.each { |subscription_id, filters| connection.subscribe(subscription_id, filters) }
			end
			connection.connect
			connection
		end

		# Subscribes every connection to +filters+ and stores them for later connections.
		def subscribe_all(subscription_id, filters)
			@mutex.synchronize do
				@subscriptions[subscription_id] = filters
				@connections.each_value { |connection| connection.subscribe(subscription_id, filters) }
			end
		end

		def stop
			@mutex.synchronize do
				@connections.each_value(&:disconnect)
				@connections.clear
			end
		end

		def status
			@mutex.synchronize do
				@connections.transform_values do |connection|
					{ state: connection.state,
						subscriptions: connection.subscriptions.keys,
						reconnect_attempts: connection.reconnect_attempts }
				end
			end
		end

		private

		def logger = Rails.logger

		# Dispatches one inbound frame to its handler by message type.
		def route(connection, message)
			type, *payload = message
			case type
			when Messages::Inbound::EVENT  then handle_event(connection, *payload)
			when Messages::Inbound::EOSE   then handle_eose(connection, *payload)
			when Messages::Inbound::CLOSED then handle_closed(connection, *payload)
			when Messages::Inbound::NOTICE then handle_notice(connection, *payload)
			when Messages::Inbound::OK     then handle_ok(connection, *payload)
			when Messages::Inbound::AUTH   then handle_auth(connection, *payload)
			else logger.debug { "[NostrClient] ignored #{type} from #{connection.url}" }
			end
		end

		def handle_event(connection, subscription_id, event)
			@on_event&.call(connection, subscription_id, event)
		end

		def handle_eose(connection, subscription_id)
			@on_eose&.call(connection, subscription_id)
		end

		def handle_closed(connection, subscription_id, reason = nil)
			connection.drop_subscription(subscription_id)
			logger.info("[NostrClient] CLOSED #{connection.url} #{subscription_id}: #{reason}")
		end

		def handle_notice(connection, text)
			logger.info("[NostrClient] NOTICE #{connection.url}: #{text}")
		end

		def handle_ok(connection, event_id, accepted, text = nil)
			logger.debug { "[NostrClient] OK #{connection.url} #{event_id} accepted=#{accepted} #{text}" }
		end

		def handle_auth(connection, challenge)
			logger.warn("[NostrClient] AUTH challenge from #{connection.url} (unanswered): #{challenge}")
		end
	end
end
