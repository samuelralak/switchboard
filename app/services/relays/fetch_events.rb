# frozen_string_literal: true

module Relays
	# A bounded, one-shot fan-out fetch over TRANSIENT NostrClient::Connections (never the persistent shared
	# Manager): open the relays, REQ the filters, collect every inbound event until each relay EOSEs or the
	# deadline passes, then disconnect. Returns the raw event hashes unfiltered -- the caller decides what to
	# keep. Runs on a job thread, NEVER the reactor (it blocks on a queue waiting for the relays to answer).
	# Because it uses its own transient connections, it never touches a live subscription, so it cannot be
	# replayed by Connection#resubscribe on a reconnect.
	class FetchEvents < BaseService
		SUBSCRIPTION = "fetch"

		option :relays
		option :filters
		option :timeout, default: -> { NostrClient.configuration.fetch_timeout_seconds }

		def call
			return [] if relays.empty?

			collect
		end

		private

		def collect
			boot
			inbox = Thread::Queue.new
			connections = relays.map { |url| open_connection(url, inbox) }
			drain(inbox)
		ensure
			connections&.each { |connection| connection&.disconnect }
		end

		def boot = NostrClient.start

		def open_connection(url, inbox)
			connection = NostrClient::Connection.new(url:, on_message: collector_for(url, inbox))
			connection.connect
			connection.subscribe(SUBSCRIPTION, filters)
			connection
		end

		# Reactor-thread callback: push each EVENT and an EOSE-per-relay onto the caller's queue.
		def collector_for(url, inbox)
			lambda do |_connection, message|
				type, *payload = message
				inbox.push([ :event, payload.last ]) if type == NostrClient::Messages::Inbound::EVENT
				inbox.push([ :eose, url ]) if type == NostrClient::Messages::Inbound::EOSE
			end
		end

		# Block the caller (a job thread, NEVER the reactor) until every relay EOSEs or the deadline elapses.
		def drain(inbox)
			pending = relays.to_set
			deadline = monotonic + timeout
			events = []
			until pending.empty?
				remaining = deadline - monotonic
				break if remaining <= 0

				message = inbox.pop(timeout: remaining) or break # nil on timeout
				kind, payload = message
				events << payload if kind == :event
				pending.delete(payload) if kind == :eose
			end
			events
		end

		def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
	end
end
