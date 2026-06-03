# frozen_string_literal: true

require "singleton"
require "eventmachine"

module NostrClient
	# Shared EventMachine reactor for all relay connections. Runs on its own
	# background thread unless EM is already running (e.g. started by Puma).
	class Reactor
		include Singleton

		BOOT_POLL_INTERVAL = 0.1 # seconds between checks that EM has come up
		SHUTDOWN_TIMEOUT = 5 # seconds to wait for our reactor thread to exit

		def initialize
			@mutex = Mutex.new
			@running = false
			@thread = nil
		end

		def start
			@mutex.synchronize do
				return if @running

				@running = true
				boot_reactor unless EM.reactor_running?
			end
		end

		def stop
			@mutex.synchronize do
				return unless @running

				shutdown_reactor
				@running = false
			end
		end

		def running? = @running && EM.reactor_running?

		# Schedule a block to run on the reactor thread (starting it if needed).
		def schedule(&)
			start unless running?
			EM.next_tick(&)
		end

		private

		# Start EM on a background thread and block until the reactor is running.
		def boot_reactor
			@thread = Thread.new { EM.run { nil } }
			sleep BOOT_POLL_INTERVAL until EM.reactor_running?
		end

		def shutdown_reactor
			return unless @thread

			EM.stop_event_loop if EM.reactor_running?
			@thread.join(SHUTDOWN_TIMEOUT)
			@thread = nil
		end
	end
end
