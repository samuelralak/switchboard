# frozen_string_literal: true

module NostrClient
	# Reconnection/backoff mixed into Connection. Capped exponential backoff with additive jitter and NO
	# permanent give-up: a relay that returns at any later time is reconnected. The backoff clears only
	# once a connection has proven stable (survived a keepalive interval), so a relay that accepts the
	# upgrade then immediately closes keeps escalating instead of reconnecting in a tight loop.
	module Reconnection
		MAX_BACKOFF_EXPONENT = 8 # 2**8 * reconnect_delay caps the exponential growth before the seconds ceiling
		JITTER_FRACTION = 0.25   # up to this fraction ADDED to the delay, to de-sync a fleet reconnecting together

		def schedule_reconnect
			return if @stopping

			@reconnect_attempts = reconnect_attempts + 1
			delay = reconnect_delay
			warn_if_degraded
			logger.info("[NostrClient] reconnecting #{url} in #{delay.round(1)}s (attempt #{reconnect_attempts})")
			# Reactor-bound timer (we are on the reactor thread in on_close): no per-close thread churn,
			# and it dies with the reactor on shutdown rather than sleeping past it.
			EM.add_timer(delay) { connect unless @stopping }
		end

		# Clear the backoff only when the link stayed open long enough to count as healthy, so a relay that
		# accepts the upgrade then immediately closes keeps escalating its backoff instead of being
		# reconnected in a tight ~2s loop. A stable connection that later drops still recovers fast.
		def reset_backoff_if_stable
			return unless @opened_at

			uptime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
			@reconnect_attempts = 0 if uptime >= NostrClient.configuration.ping_interval_seconds
			@opened_at = nil
		end

		private

		# Exponential backoff with a seconds ceiling and up to +25% additive jitter. Jitter de-syncs
		# reconnects so a recovering relay is not hammered in lockstep.
		def reconnect_delay
			config = NostrClient.configuration
			exponent = [ reconnect_attempts - 1, MAX_BACKOFF_EXPONENT ].min
			base = [ config.reconnect_delay_seconds * (2**exponent), config.max_reconnect_delay_seconds ].min
			base + (rand * JITTER_FRACTION * base)
		end

		# One WARN as we cross the configured attempt cap, so a sustained outage is observable. Past the
		# cap the relay is NOT abandoned: backoff has simply settled at its ceiling and keeps retrying.
		def warn_if_degraded
			config = NostrClient.configuration
			return unless reconnect_attempts == config.max_reconnect_attempts + 1

			logger.warn("[NostrClient] #{url} degraded after #{reconnect_attempts} failed reconnects; still retrying")
		end
	end
end
