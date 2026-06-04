# frozen_string_literal: true

require "singleton"

module NostrClient
	# Holds the relay connections and dispatches inbound NIP-01 frames by type.
	# EVENT/EOSE reach the consumer hooks, CLOSED retires the subscription (or re-auths on
	# auth-required), OK resolves a pending publish, AUTH answers the NIP-42 challenge, and
	# NOTICE is logged. Active subscriptions are applied to connections added later.
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

		# Publishes a signed event to every connection and returns a PublishResult per relay. Arms all
		# relays first, then collects, so total latency is ~one timeout, not N relays times the timeout.
		def publish(event_hash)
			@mutex.synchronize { @connections.values }.map { |connection| connection.publish_async(event_hash) }.map(&:pop)
		end

		def stop
			@mutex.synchronize do
				@connections.each_value(&:disconnect)
				@connections.clear
			end
		end

		def status
			@mutex.synchronize { @connections.transform_values { |conn| connection_status(conn) } }
		end

		private

		def logger = Rails.logger

		def connection_status(conn)
			{ state: conn.state, subscriptions: conn.subscriptions.keys, reconnect_attempts: conn.reconnect_attempts }
		end

		# Validates the inbound frame's shape, then dispatches it to its handler by message type.
		def route(connection, message)
			type, *payload = message
			return logger.debug { "[NostrClient] malformed #{type} from #{connection.url}" } if malformed?(type, payload)

			dispatch(connection, type, payload)
		end

		# The NIP-01 type -> handler table (payload arity already checked by #malformed?).
		def dispatch(connection, type, payload)
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
			return connection.authenticate if connection.auth_required?(reason)

			connection.drop_subscription(subscription_id)
			logger.info("[NostrClient] CLOSED #{connection.url} #{subscription_id}: #{reason}")
		end

		def handle_notice(connection, text)
			logger.info("[NostrClient] NOTICE #{connection.url}: #{text}")
		end

		def handle_ok(connection, event_id, accepted, text = nil)
			connection.settle_ok(event_id, accepted, text)
		end

		# Lazy AUTH: only store the relay's challenge. We sign and send the AUTH credential later, and
		# only if a gated operation actually needs it (see Publishing#defer_until_authenticated).
		def handle_auth(connection, challenge)
			connection.store_challenge(challenge)
		end

		# A known frame whose payload arity is outside its NIP-01/42 shape is malformed (too few OR too
		# many elements); unknown types are not validated here (they fall through to the dispatch else).
		def malformed?(type, payload)
			arity = payload_arity(type) or return false

			!arity.cover?(payload.size)
		end

		# Accepted payload-element count per known inbound frame (relay -> client exact shapes):
		# EVENT [sub, event]; OK [id, ok, msg?]; CLOSED [sub, msg?]; EOSE/NOTICE/AUTH single-element.
		def payload_arity(type)
			case type
			when Messages::Inbound::EVENT then 2..2
			when Messages::Inbound::OK then 2..3
			when Messages::Inbound::CLOSED then 1..2
			when Messages::Inbound::EOSE, Messages::Inbound::NOTICE, Messages::Inbound::AUTH then 1..1
			end
		end
	end
end
