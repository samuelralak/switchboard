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

		# Boot the reactor (idempotent). Returns the manager for chaining.
		def start
			reactor.start
			manager
		end

		# Open persistent publish connections in a process that needs to SEND (the Puma web process), as
		# opposed to the relay:boot ingest process which opens its own via Relays::Sync. Idempotent:
		# add_connection dedupes a url already held, so it is safe to call once per worker after fork.
		def boot_publishing!(urls = configuration.dm_relays)
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
