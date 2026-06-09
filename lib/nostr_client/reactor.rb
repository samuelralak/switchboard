# frozen_string_literal: true

require "singleton"
require "eventmachine"

module NostrClient
	# Shared EventMachine reactor for all relay connections. Runs on its own
	# background thread unless EM is already running (e.g. started by Puma).
	class Reactor
		include Singleton

		BOOT_POLL_INTERVAL = 0.1 # seconds between checks that EM has come up
		BOOT_TIMEOUT = 5 # seconds to wait for EM to come up before giving up (rather than hang forever)
		SHUTDOWN_TIMEOUT = 5 # seconds to wait for our reactor thread to exit

		def initialize
			@mutex = Mutex.new
			@running = false
			@thread = nil
		end

		def start
			@mutex.synchronize do
				# Re-boot only if the reactor thread is actually DEAD (an unhandled non-StandardError escaped, or
				# it was killed) -- a stale @running=true with a dead thread would otherwise wedge every future
				# schedule. Gating on @thread.alive? (not EM.reactor_running?) is deliberate: during the boot
				# window the thread is alive but EM is not yet up, and gating on EM.reactor_running? there would
				# let a concurrent start() double-spawn the thread. Healthy/booting just falls through to the wait.
				unless @running && @thread&.alive?
					@running = true
					boot_reactor unless EM.reactor_running?
				end
			end
			# Wait for EM OUTSIDE the lock so a concurrent start() does not serialize behind the boot; every
			# caller waits, not just the one that spawned the thread, so none schedules before EM is up.
			wait_until_running
		end

		def stop
			@mutex.synchronize do
				return unless @running

				shutdown_reactor
				@running = false
			end
		end

		def running? = @running && EM.reactor_running?

		# Clear stale reactor state after a fork: EM does not survive fork, so a forked worker that inherited
		# @running=true must re-init or schedule() would no-op onto a dead reactor. Call from a post-fork hook.
		def reset
			@mutex.synchronize do
				@running = false
				@thread = nil
			end
		end

		# Schedule a block to run on the reactor thread (starting it if needed).
		def schedule(&)
			start unless running?
			EM.next_tick(&)
		end

		private

		# Spawn the EM thread (the wait happens in #start, off the lock). The error_handler is the process-level
		# boundary: without it, ONE unhandled exception in any reactor-scheduled block (a send/ping on a bad
		# socket) propagates out of EM.run, kills this single shared thread, and strands every publisher
		# blocked in publish_async#pop forever. With it, the block error is logged and the reactor survives.
		# Log only class + message (never the exception object) so no frame/event payload can leak.
		def boot_reactor
			@thread = Thread.new do
				Thread.current.name = "nostr-reactor"
				EM.run { EM.error_handler { |error| log_reactor_error(error) } }
			end
		end

		# Log only class + message (never the exception object) so no frame/event payload can leak.
		def log_reactor_error(error)
			Rails.logger.error("[NostrClient] reactor block error: #{error.class}: #{error.message}")
		end

		def wait_until_running
			deadline = BOOT_TIMEOUT / BOOT_POLL_INTERVAL
			deadline.to_i.times do
				return unless @running # a stop() raced the boot window: unwind quietly instead of timing out

				return if EM.reactor_running?

				sleep BOOT_POLL_INTERVAL
			end
			raise NostrClient::Error, "EventMachine reactor did not start within #{BOOT_TIMEOUT}s" unless EM.reactor_running?
		end

		def shutdown_reactor
			return unless @thread

			EM.stop_event_loop if EM.reactor_running?
			unless @thread.join(SHUTDOWN_TIMEOUT)
				Rails.logger.warn("[NostrClient] reactor thread did not exit in #{SHUTDOWN_TIMEOUT}s; killing")
				@thread.kill
			end
			@thread = nil
		end
	end
end
