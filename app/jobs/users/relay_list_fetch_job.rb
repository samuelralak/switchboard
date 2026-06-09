# frozen_string_literal: true

module Users
	# Fetches + ingests a user's NIP-65 relay list, enqueued on login by Sessions::Authenticate. The fetched
	# kind:10002 goes through the normal verify+store path (Catalog::Ingest -> Events::Upsert), which projects
	# it into user_relays via the after-commit RelayListProjectJob. A per-pubkey cooldown keeps re-logins from
	# re-fetching a long-lived (replaceable) event. Reading kind:10002 needs no key, so this stays non-custodial.
	class RelayListFetchJob < ApplicationJob
		queue_as :ingest

		COOLDOWN = 1.hour
		SOURCE = "indexer"

		def perform(pubkey)
			# fetch runs once per cooldown window: the block executes only on a cache miss, then the result is
			# cached, so re-logins within the window skip the relay round-trip. A raise is not cached (retryable).
			Rails.cache.fetch("users:relay_list_fetch:#{pubkey}", expires_in: COOLDOWN) do
				event = RelayListFetch.call(pubkey:)
				Catalog::Ingest.call(event_data: event, source_relay: SOURCE) if event
				true
			end
		end
	end
end
