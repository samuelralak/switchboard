# frozen_string_literal: true

# A small outbound Nostr relay client: maintains persistent WebSocket
# connections to relays (on a shared EventMachine reactor), subscribes with
# NIP-01 filters, and routes inbound EVENT/EOSE/NOTICE/CLOSED to handlers.
#
#   NostrClient.configure { |c| c.relays = ["wss://relay.damus.io"] }
#   NostrClient.manager.on_event { |conn, sub_id, event| ... }
#   NostrClient.start
#   conn = NostrClient.manager.add_connection("wss://relay.damus.io")
#   conn.subscribe("listings", [{ kinds: [30402], limit: 200 }])
module NostrClient
	class Error < StandardError
	end

	class << self
		def configuration = Configuration.config

		def configure(&)
			Configuration.configure(&) if block_given?
			Configuration.config
		end

		def reactor = Reactor.instance
		def manager = Manager.instance

		# True only while the shared reactor thread is alive and EM is up; false once it dies. The relay:boot
		# supervisor polls this so a dead reactor exits the process (and Fly restarts it) instead of going stale.
		delegate :running?, to: :reactor

		# Boot the reactor (idempotent). Returns the manager for chaining.
		def start
			reactor.start
			manager
		end

		# Open persistent publish connections in a process that needs to SEND (the Puma web process), as
		# opposed to the relay:boot ingest process which opens its own via Relays::Sync. Connects to BOTH the
		# public catalog relays (where server-signed public events like attestation labels go) and the DM-inbox
		# relays (where NIP-17 wraps go); callers pick the right subset per event via Manager#publish(urls:), so
		# the two never share a destination. Idempotent: add_connection dedupes a url already held.
		def boot_publishing!(urls = (configuration.relays + configuration.dm_relays).uniq)
			start
			urls.each { |url| manager.add_connection(url) }
			manager
		end

		# Tear down all connections and stop the reactor (if we own it).
		def stop
			manager.stop
			reactor.stop
		end
	end
end
