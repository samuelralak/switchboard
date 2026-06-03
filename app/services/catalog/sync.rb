# frozen_string_literal: true

module Catalog
	# Connects NostrClient to every configured relay, subscribes to the NIP-99 catalog
	# (kind 30402), and enqueues a Catalog::IngestJob per inbound event. Backs relay:boot.
	class Sync
		extend Dry::Initializer

		SUBSCRIPTION = "listings"

		option :limit, type: Types::Coercible::Integer, default: -> { 200 }

		delegate :stop, to: :NostrClient

		# Subscriptions are recorded before connecting; each relay sends its REQ on open.
		def start
			listen_for_events
			subscribe_to_catalog
			NostrClient.start
			open_connections
			self
		end

		private

		# Register the handler before connecting, so no inbound event is missed.
		def listen_for_events
			NostrClient.manager.on_event { |connection, _sub_id, event_data| enqueue(connection, event_data) }
		end

		def open_connections
			NostrClient.configuration.relays.each { |url| NostrClient.manager.add_connection(url) }
		end

		def subscribe_to_catalog
			NostrClient.manager.subscribe_all(SUBSCRIPTION, catalog_filters)
		end

		def catalog_filters
			[ { kinds: [ Events::Kinds::CLASSIFIED ], limit: } ]
		end

		# Off the reactor thread onto Solid Queue, wrapped in the Rails executor.
		def enqueue(connection, event_data)
			Rails.application.executor.wrap do
				IngestJob.perform_later(event_data.to_json, connection.url)
			end
		rescue StandardError => e
			Rails.logger.error("[Catalog::Sync] enqueue error: #{e.class}: #{e.message}")
		end
	end
end
