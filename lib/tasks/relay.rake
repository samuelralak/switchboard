# frozen_string_literal: true

namespace :relay do
	desc "Run the persistent relay ingest in the foreground (the `relay:` process). Ctrl-C to stop."
	task boot: :environment do
		sync = Relays::Sync.new.start
		stopping = false
		%w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
		ids = Relays::Registry.instance.all.map(&:id).join(", ")
		puts "Relay ingest running (#{ids}). Ctrl-C to stop."
		sleep 1 until stopping
	ensure
		sync&.stop
	end
end
