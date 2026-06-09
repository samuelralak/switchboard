# frozen_string_literal: true

module Catalog
	# Builds the catalog's relay-ingest subscription: pull NIP-99 classifieds (kind 30402) into the catalog,
	# resuming from the persisted high-water-mark, ingesting each matched event via Catalog::IngestJob. The
	# relay subsystem (Relays::) owns everything else (connections, reconcile, replay, backfill); the catalog
	# is just a consumer that registers this spec with Relays::Registry at boot (config/initializers/relays.rb).
	class RelaySubscription < BaseService
		option :cursor, default: -> { Cursor.new }

		# limit is omitted: the catalog inherits NostrClient.configuration.subscription_limit (the relay-wide
		# default), keeping the ingest pull bound in one place.
		def call
			Relays::Subscription.new(id: "listings", kinds: [ Events::Kinds::CLASSIFIED ], cursor:, ingest: IngestJob)
		end
	end
end
