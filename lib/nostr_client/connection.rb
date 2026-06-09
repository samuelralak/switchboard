# frozen_string_literal: true

require "dry-initializer"
require "eventmachine"
require "faye/websocket"
require "json"

module NostrClient
	# A single WebSocket connection to one relay: manages socket lifecycle, exponential-backoff
	# reconnection (never permanently abandoned), keepalive half-open detection, and subscriptions.
	# Inbound frames are forwarded to the `on_message` callable for NIP-01 dispatch. Publishing (OK
	# correlation) and NIP-42 AUTH are mixed in.
	class Connection
		extend Dry::Initializer
		include Publishing
		include Authentication
		include Keepalive
		include Reconnection

		option :url, type: Types::RelayUrl
		option :on_message, type: Types::Callable, reader: :private
		# Per-connection lock: callers (Puma threads via Manager) and the reactor thread both touch the
		# state machine and the subscription table, so the compound check-then-act paths are guarded.
		option :mutex, default: -> { Mutex.new }, reader: :private
		option :subscriptions, default: -> { {} }

		def state = @state || :disconnected
		def reconnect_attempts = @reconnect_attempts || 0
		def connected? = state == :connected

		def connect
			mutex.synchronize do
				return if %i[connecting connected].include?(state)

				@state = Types::ConnectionState[:connecting]
			end
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
			mutex.synchronize { subscriptions[subscription_id] = filters }
			send_frame(Messages::Outbound::REQ, subscription_id, *filters) if connected?
		end

		# Removes a tracked subscription and tells the relay to stop it (NIP-01 CLOSE); send_frame
		# no-ops when disconnected, so a relay that already dropped the sub is not contacted.
		def drop_subscription(subscription_id)
			mutex.synchronize { subscriptions.delete(subscription_id) }
			send_frame(Messages::Outbound::CLOSE, subscription_id)
		end

		private

		def logger = Rails.logger

		# Sets @state, validating against Types::ConnectionState.
		def transition_to(next_state)
			mutex.synchronize { @state = Types::ConnectionState[next_state] }
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
			@opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
			logger.info("[NostrClient] connected #{url}")
			resubscribe
			start_keepalive
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
			stop_keepalive
			reconnecting = !@stopping && state != :closing
			reset_backoff_if_stable
			transition_to(:disconnected)
			fail_all("disconnected")
			reset_auth
			logger.info("[NostrClient] disconnected #{url} code=#{event.code}")
			schedule_reconnect if reconnecting
		end

		# Iterate a snapshot: subscribe/drop_subscription (Puma threads) may mutate the table while the
		# reactor thread is re-applying it on reconnect.
		def resubscribe
			snapshot = mutex.synchronize { subscriptions.dup }
			snapshot.each { |subscription_id, filters| send_frame(Messages::Outbound::REQ, subscription_id, *filters) }
		end

		def send_frame(*frame)
			return unless connected?

			socket = @socket # capture: a reconnect can replace @socket before this scheduled block runs
			json = frame.to_json
			Reactor.instance.schedule { socket&.send(json) }
		end
	end
end
