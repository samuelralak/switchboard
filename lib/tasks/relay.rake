# frozen_string_literal: true

namespace :relay do
	desc "Run the persistent relay connection in the foreground (the `relay:` process). Ctrl-C to stop."
	task boot: :environment do
		sync = Catalog::Sync.new(limit: 500).start
		stopping = false
		%w[INT TERM].each { |signal| Signal.trap(signal) { stopping = true } }
		puts "Relay client running (kind #{Events::Kinds::CLASSIFIED}). Ctrl-C to stop."
		sleep 1 until stopping
	ensure
		sync&.stop
	end
end
