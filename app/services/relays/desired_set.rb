# frozen_string_literal: true

module Relays
	# The relay set the ingest SHOULD be connected to: the always-on seeds plus the most-covered user WRITE
	# relays (NIP-65 outbox) of active-session users, deterministically ranked by author coverage and bounded
	# by a global ceiling. Connections therefore scale with the count of DISTINCT relay urls, never with the
	# number of users; the busiest relays win the budget and one user cannot evict a popular relay. Seeds are
	# always included and never counted against the ceiling.
	class DesiredSet < BaseService
		option :seeds, default: -> { NostrClient.configuration.relays }
		option :ceiling, default: -> { NostrClient.configuration.max_relays }

		def call
			(seeds + top_user_relays).uniq
		end

		private

		# Each active user's write relays, capped per-user to max_write_relays_per_user, then ranked globally by
		# author coverage and bounded by the global ceiling. Per-user capping means one user with a long list
		# cannot crowd out other users' relays from the global budget. The window ROW_NUMBER lives in a
		# subquery (per_user_ranked); the rn filter must be in this OUTER query, since a window alias is not
		# visible to the WHERE of the query that defines it.
		def top_user_relays
			capped = UserRelay.from(per_user_ranked, :user_relays).where(rn: ..per_user_cap)
			capped.group(:url).order(Arel.sql("COUNT(*) DESC, url ASC")).limit(ceiling).pluck(:url)
		end

		# Inner subquery: each active user's write relays, numbered per-user (deterministic url order, so the
		# same subset is chosen every tick). COUNT(*) over the capped set == distinct-author coverage, since
		# (pubkey, url) is unique.
		def per_user_ranked
			window = Arel.sql("ROW_NUMBER() OVER (PARTITION BY pubkey ORDER BY url) AS rn")
			UserRelay.writeable.where(pubkey: active_pubkeys).select(:url, window)
		end

		def per_user_cap = NostrClient.configuration.max_write_relays_per_user

		# Only users with a live session pin relays, so a dormant user's relays age out of the desired set.
		def active_pubkeys
			User.joins(:sessions).merge(Session.active).select(:pubkey)
		end
	end
end
