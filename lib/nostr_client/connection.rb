# frozen_string_literal: true

require "dry-initializer"
require "eventmachine"
require "faye/websocket"
require "json"

module NostrClient
	# A single WebSocket connection to one relay: manages socket lifecycle, linear-backoff
	# reconnection, and subscriptions. Inbound frames are forwarded to the `on_message` callable
	# for NIP-01 dispatch. Publishing (OK correlation) and NIP-42 AUTH are mixed in.
	class Connection
		extend Dry::Initializer
		include Publishing
		include Authentication

		option :url, type: Types::RelayUrl
		option :on_message, type: Types::Callable, reader: :private

		def state = @state ||= :disconnected
		def subscriptions = @subscriptions ||= {}
		def reconnect_attempts = @reconnect_attempts ||= 0
		def connected? = state == :connected

		def connect
			return if %i[connecting connected].include?(state)

			transition_to(:connecting)
			Reactor.instance.schedule { open_socket }
		end

		def disconnect
			@stopping = true
			return if state == :disconnected

			transition_to(:closing)
			Reactor.instance.schedule { @socket&.close }
		end

		# Records the subscription and sends REQ if connected.
		def subscribe(subscription_id, filters)
			subscriptions[subscription_id] = filters
			send_frame(Messages::Outbound::REQ, subscription_id, *filters) if connected?
		end

		# Removes a tracked subscription and tells the relay to stop it (NIP-01 CLOSE); send_frame
		# no-ops when disconnected, so a relay that already dropped the sub is not contacted.
		def drop_subscription(subscription_id)
			subscriptions.delete(subscription_id)
			send_frame(Messages::Outbound::CLOSE, subscription_id)
		end

		private

		def logger = Rails.logger

		# Sets @state, validating against Types::ConnectionState.
		def transition_to(next_state)
			@state = Types::ConnectionState[next_state]
		end

		def open_socket
			@socket = Faye::WebSocket::Client.new(url)
			@socket.on(:open)    { on_open }
			@socket.on(:message) { |event| on_frame(event.data) }
			@socket.on(:close)   { |event| on_close(event) }
			@socket.on(:error)   { |event| logger.warn("[NostrClient] error #{url}: #{event.message}") }
		end

		def on_open
			transition_to(:connected)
			@reconnect_attempts = 0
			logger.info("[NostrClient] connected #{url}")
			resubscribe
		end

		# Parses one frame and forwards arrays to on_message; logs and drops on error.
		def on_frame(data)
			message = JSON.parse(data)
			on_message.call(self, message) if message.is_a?(Array)
		rescue StandardError => e
			logger.error("[NostrClient] dropped frame from #{url}: #{e.class}: #{e.message}")
		end

		# Reconnect unless we are stopping or the close was deliberate, so a relay that was
		# unreachable at boot is retried too, not only one that dropped after opening.
		def on_close(event)
			reconnecting = !@stopping && state != :closing
			transition_to(:disconnected)
			fail_all("disconnected")
			reset_auth
			logger.info("[NostrClient] disconnected #{url} code=#{event.code}")
			schedule_reconnect if reconnecting
		end

		def resubscribe
			subscriptions.each { |subscription_id, filters| send_frame(Messages::Outbound::REQ, subscription_id, *filters) }
		end

		def schedule_reconnect
			return if @stopping

			config = NostrClient.configuration
			@reconnect_attempts = reconnect_attempts + 1
			return if @reconnect_attempts > config.max_reconnect_attempts

			delay = config.reconnect_delay_seconds * @reconnect_attempts
			logger.info("[NostrClient] reconnecting #{url} in #{delay}s (attempt #{@reconnect_attempts})")
			# Reactor-bound timer (we are on the reactor thread in on_close): no per-close thread churn,
			# and it dies with the reactor on shutdown rather than sleeping past it.
			EM.add_timer(delay) { connect unless @stopping }
		end

		def send_frame(*frame)
			return unless connected?

			json = frame.to_json
			Reactor.instance.schedule { @socket&.send(json) }
		end
	end
end
