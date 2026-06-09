# frozen_string_literal: true

module NostrClient
	# Keepalive mixed into Connection: detect a silent half-open socket the OS/relay never closed. Ping on
	# an interval; if the matching PONG does not return within pong_timeout_seconds the link is half-open,
	# so force-close it and let on_close drive the reconnect. faye fires the ping block on PONG (a dead
	# link never does). All on the reactor thread, armed in on_open and torn down in on_close.
	module Keepalive
		def start_keepalive
			interval = NostrClient.configuration.ping_interval_seconds
			@ping_timer = EM.add_periodic_timer(interval) { send_ping }
		end

		# Never overlap pings: faye keys the PONG callback by payload, so a second outstanding ping would
		# collapse onto the first's slot and (if pong_timeout >= ping_interval) force-close a healthy socket.
		def send_ping
			return if @pong_deadline

			socket = @socket
			return unless socket

			@pong_deadline = EM.add_timer(NostrClient.configuration.pong_timeout_seconds) { socket.close }
			# ping returns false on a socket past OPEN: no PONG will arrive, so drop the deadline now.
			clear_pong_deadline unless socket.ping { clear_pong_deadline }
		end

		def clear_pong_deadline
			EM.cancel_timer(@pong_deadline) if @pong_deadline
			@pong_deadline = nil
		end

		def stop_keepalive
			EM.cancel_timer(@ping_timer) if @ping_timer
			clear_pong_deadline
			@ping_timer = nil
		end
	end
end
