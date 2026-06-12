# frozen_string_literal: true

module Users
	# Fetches + ingests a user's NIP-65 relay list, enqueued on login by Sessions::Authenticate, and again with
	# force: true after a browser relay-list edit, so the just-broadcast kind:10002 is pulled back
	# deterministically. The fetched event goes through the normal verify+store path (Catalog::Ingest ->
	# Events::Upsert), which projects it into user_relays via the after-commit RelayListProjectJob. A per-pubkey
	# cooldown keeps re-logins from re-fetching a long-lived (replaceable) event; an edit passes force: true to
	# bypass it. Reading kind:10002 needs no key, so this stays non-custodial. Mirrors Users::MetadataFetchJob.
	class RelayListFetchJob < ApplicationJob
		queue_as :ingest

		COOLDOWN = 1.hour
		SOURCE = "indexer"

		def perform(pubkey, force: false)
			# The block runs once per cooldown window (or always when forced), then the result is cached, so
			# re-logins within the window skip the relay round-trip. A raise is not cached (retryable).
			Rails.cache.fetch("users:relay_list_fetch:#{pubkey}", expires_in: COOLDOWN, force:) do
				event = RelayListFetch.call(pubkey:, relays: relays_for(pubkey))
				Catalog::Ingest.call(event_data: event, source_relay: SOURCE) if event
				true
			end
		end

		private

		# Read from the discovery indexers (where a pre-existing list lives at login) PLUS where a browser edit
		# broadcasts (the catalog relays + the user's own NIP-65 write relays), so a forced post-edit fetch
		# reliably finds the fresh event.
		def relays_for(pubkey)
			config = NostrClient.configuration
			(config.indexer_relays + config.relays + UserRelay.writeable.where(pubkey:).pluck(:url)).uniq
		end
	end
end
