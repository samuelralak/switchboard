# frozen_string_literal: true

module Users
	# Fetches + ingests a user's kind-0 profile. Enqueued on login by Sessions::Authenticate (this is what
	# populates the User profile projection at all -- nothing subscribes to kind-0), and again with force: true
	# after a browser profile edit, so the just-broadcast kind-0 is pulled back deterministically. The fetched
	# event goes through the normal verify+store path (Catalog::Ingest -> Events::Upsert), which projects it
	# onto the User row via the after-commit Users::ProjectJob. A per-pubkey cooldown keeps re-logins from
	# re-fetching a long-lived (replaceable) event; an edit passes force: true to bypass it. Reading kind:0
	# needs no key, so this stays non-custodial. Mirrors Users::RelayListFetchJob.
	class MetadataFetchJob < ApplicationJob
		queue_as :ingest

		COOLDOWN = 1.hour
		SOURCE = "indexer"

		def perform(pubkey, force: false)
			# The block runs once per cooldown window (or always when forced), then the result is cached, so
			# re-logins within the window skip the relay round-trip. A raise is not cached (retryable).
			Rails.cache.fetch("users:metadata_fetch:#{pubkey}", expires_in: COOLDOWN, force:) do
				event = MetadataFetch.call(pubkey:, relays: relays_for(pubkey))
				Catalog::Ingest.call(event_data: event, source_relay: SOURCE) if event
				true
			end
		end

		private

		# Read from a superset of where the browser broadcasts a profile edit (the catalog relays) so a forced
		# post-edit fetch reliably finds the fresh event, PLUS the discovery indexers and the user's own NIP-65
		# write relays so the login fetch finds a pre-existing profile that never touched our relays.
		def relays_for(pubkey)
			config = NostrClient.configuration
			(config.relays + config.indexer_relays + UserRelay.writeable.where(pubkey:).pluck(:url)).uniq
		end
	end
end
