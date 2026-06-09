# frozen_string_literal: true

module Relays
	# What a domain wants ingested from the relay set, decoupled from WHERE it comes from. The relay
	# subsystem owns connections, reconcile, replay and backfill; a Subscription declares only the kinds to
	# pull, an optional cursor for a resumable live `since`, and the job that ingests each matched event. The
	# same spec drives both the persistent live subscription (carrying the cursor's since) and the one-shot
	# backlog pull of a newly added relay (no since, separately bounded). `id` is the NIP-01 subscription_id
	# that tags REQ frames and routes inbound events back to this spec's ingest. Adding a consumer (e.g.
	# notes) is one Subscription, never a parallel relay module.
	class Subscription
		extend Dry::Initializer

		option :id
		option :kinds
		option :ingest
		option :cursor, default: -> { }
		option :limit, default: -> { NostrClient.configuration.subscription_limit }

		# The live filter resumes from the cursor's high-water-mark; a first-ever boot (no since) pulls the
		# bounded initial window.
		def live_filters = [ filter(limit, cursor&.since) ]

		# The backfill filter carries NO since: a freshly added relay must surface its backlog OLDER than the
		# global live cursor, bounded on its own.
		def backfill_filters = [ filter(NostrClient.configuration.backfill_limit) ]

		# Hand a matched event to the consumer's ingest. (json, source_url) is the one ingest contract every
		# consumer's job implements.
		def enqueue(event, source_url) = ingest.perform_later(event.to_json, source_url)

		private

		def filter(limit, since = nil)
			query = { kinds:, limit: }
			query[:since] = since if since
			query
		end
	end
end
