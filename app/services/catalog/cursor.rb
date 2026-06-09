# frozen_string_literal: true

module Catalog
	# The catalog ingest high-water-mark: the NIP-01 created_at of the newest event ingested, persisted so
	# a relay:boot restart resumes with a `since` filter instead of re-pulling the whole catalog. A small
	# OVERLAP is subtracted on read to absorb relay/clock skew; Events::Upsert idempotency makes the
	# replayed overlap harmless. Set once per boot into the subscription filter (Manager holds static
	# filters), so it recovers the cross-restart gap; mid-process gaps are bounded by reconnect backoff.
	# The cache store is injected (dry-initializer) so it can be exercised against a real store in tests.
	#
	# Best-effort by design. (1) The store is Solid Cache (size-bounded, no read-touch), so the cold key may
	# be evicted under pressure; #since then returns nil and the next boot does a full, limit-bounded re-pull
	# (harmless via Upsert idempotency). (2) It is a SINGLE global watermark, so it assumes gapless ingest: a
	# dropped enqueue (a transient queue-DB failure, logged in Catalog::Sync#enqueue) can be skipped once a
	# faster relay advances the HWM past it, until that listing is re-published or the key is evicted. A
	# per-relay watermark (the source_relay column exists) would close that, but needs per-connection filters
	# in Manager, so it is a deferred cursor-model change, not a stability fix.
	class Cursor
		extend Dry::Initializer

		KEY = "catalog:ingest:hwm"
		OVERLAP = 60 # seconds re-requested before the high-water-mark, against clock skew

		option :store, default: -> { Rails.cache }, reader: :private

		# The `since` to resume from (high-water-mark minus the overlap), or nil if nothing ingested yet.
		def since
			hwm = store.read(KEY)
			hwm && (hwm - OVERLAP)
		end

		# Advance the high-water-mark to +created_at+ when it is newer. A relay replaying an old event never
		# advances it. The read-then-write is NOT atomic and the cache has no CAS, so concurrent ingest jobs
		# can transiently leave the HWM below the running max (a stale reader's lower value lands last). That
		# is the safe direction: a lower HWM only widens the next `since` (harmless over-fetch via Upsert
		# idempotency), never skips events. A lock is unwarranted for a safe-direction regression.
		def advance(created_at)
			return unless created_at

			# Clamp to wall-clock now: Events::Contract accepts a created_at up to 15 min in the future, and a
			# future-dated HWM would push the next boot's `since` PAST genuinely-arriving events (a real skip,
			# not a safe over-fetch). Clamping keeps `since <= now - OVERLAP`, so the resume can never exclude
			# a currently-arriving event; the cost is at most a slightly wider, idempotent over-fetch.
			value = [ created_at, Time.now.to_i ].min
			current = store.read(KEY)
			store.write(KEY, value) if current.nil? || value > current
		end
	end
end
