# frozen_string_literal: true

module Relays
	# Reconcile the open relay connections toward the desired set. The DB is the source of truth, so this is
	# trustless (recompute, never trust a payload) and self-heals on restart. ADD: a relay that becomes
	# desired (a user logged in and advertised it) is opened, Manager#add_connection is idempotent + replays
	# every active subscription onto it, and a one-shot backfill is enqueued PER registered subscription so
	# the relay's pre-cursor backlog is pulled for every consumer (catalog today, notes tomorrow). EVICT: a
	# relay no longer desired is closed, but only after TEARDOWN_GRACE CONSECUTIVE undesired ticks, so a
	# transient dip in active sessions does not thrash connections. Seeds are never evicted -- they are always
	# in the desired set, so they never enter the undesired set.
	class Reconcile < BaseService
		# One cache entry holds { url => consecutive-undesired-tick-count } for the current eviction
		# candidates; it is rewritten wholesale each tick, so a relay that re-enters the desired set drops out
		# and its countdown resets (exact "consecutive" semantics).
		CANDIDATES_KEY = "relays:eviction_candidates"

		option :manager, default: -> { NostrClient.manager }
		option :registry, default: -> { Registry.instance }
		option :store, default: -> { Reconcile.candidate_store }

		# Per-process in-memory store for the eviction-candidate tick counts. relay:boot is a single long-lived
		# process (it owns the singleton reactor + connections), so this is per-process state by nature; keeping
		# it OUT of the shared Solid Cache avoids a cross-process read-modify-write race and needs no
		# serialization. A restart resets it, which is correct: connections reset too, so the grace countdown
		# legitimately starts fresh.
		def self.candidate_store
			@candidate_store ||= ActiveSupport::Cache::MemoryStore.new
		end

		def call
			desired = DesiredSet.call
			open = manager.connection_urls
			add(desired - open)
			evict(open - desired)
		end

		private

		def add(new_relays)
			subscriptions = registry.all
			new_relays.each do |url|
				manager.add_connection(url)
				subscriptions.each { |subscription| BackfillJob.perform_later(url, subscription.id) }
			end
		end

		# Tally each undesired relay; evict the ones that have now been undesired for the full grace window,
		# carry the rest forward, and drop (reset) any that are no longer undesired.
		def evict(undesired)
			counts = store.read(CANDIDATES_KEY) || {}
			carried = {}
			undesired.each do |url|
				tally = counts.fetch(url, 0) + 1
				tally >= grace ? manager.remove_connection(url) : carried[url] = tally
			end

			store.write(CANDIDATES_KEY, carried, expires_in: candidates_ttl)
		end

		def grace = NostrClient.configuration.teardown_grace_ticks

		def candidates_ttl = NostrClient.configuration.reconcile_interval_seconds * (grace + 2)
	end
end
