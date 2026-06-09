# frozen_string_literal: true

module Relays
	# One-shot backlog pull for a relay newly added to the ingest. A live subscription carries the global
	# since-cursor, so a freshly added relay would skip events OLDER than the cursor -- exactly the ones the
	# seeds did not carry. This fetches that relay's backlog (no since) over a SEPARATE transient connection
	# (Relays::FetchEvents), so it never touches the live subscriptions and thus cannot be replayed by
	# Connection#resubscribe on a reconnect, then feeds each event through the subscription's own ingest
	# (idempotent). Runs once per (subscription, url) ever (a Solid Cache flag), so a flapping relay or a
	# reconcile re-adding the url never re-pulls the backlog.
	class BackfillJob < ApplicationJob
		queue_as :ingest

		def perform(url, subscription_id)
			subscription = Registry.instance.find(subscription_id) or return

			ttl = NostrClient.configuration.backfill_flag_ttl_seconds
			Rails.cache.fetch("relays:backfilled:#{subscription_id}:#{url}", expires_in: ttl) do
				FetchEvents.call(relays: [ url ], filters: subscription.backfill_filters).each do |event|
					subscription.enqueue(event, url)
				end
				true
			end
		end
	end
end
