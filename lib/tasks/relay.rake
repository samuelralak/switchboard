# frozen_string_literal: true

namespace :relay do
	desc "Run the persistent relay ingest in the foreground (the `relay:` process). Ctrl-C to stop."
	task boot: :environment do
		sync = Relays::Sync.new.start
		stopping = false
		%w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
		ids = Relays::Registry.instance.all.map(&:id).join(", ")
		puts "Relay ingest running (#{ids}). Ctrl-C to stop."

		# The reactor runs on a background thread; if it dies (an unhandled error escaped EM) the read-model
		# freezes. Break out and exit non-zero so the supervisor (Fly) restarts the machine, rather than leaving
		# a live-but-dead ingest no health check can see. A signal (stopping) is the only clean exit.
		until stopping
			break unless NostrClient.running?

			sleep 1
		end

		abort "[relay:boot] reactor stopped unexpectedly; exiting so the supervisor restarts it" unless stopping
	ensure
		sync&.stop
	end
end
