# frozen_string_literal: true

module Relays
	# The relay set a user PUBLISHES their own events to: the platform seed relays unioned (additively) with
	# the user's own NIP-65 WRITE relays (their outbox), so a listing/request/profile/relay-list reaches the
	# relays they advertise without ever dropping the seeds the catalog ingest reads. config/relays.yml states
	# this "added on top of the seeds" contract; this is where the browser publish paths read it. Deduped on
	# the canonical url (seeds and user_relays.url share Shared::NormalizeRelayUrl's canonical form). A
	# signed-out user, or one with no write relays yet, publishes to the seeds alone. The set is bounded: the
	# kind-10002 projection caps a user at a small write set, so this never fans out to an unbounded list.
	class PublishSet < BaseService
		option :user

		def call
			return seeds unless user

			(seeds + user.user_relays.writeable.order(:url).pluck(:url)).uniq
		end

		private

		def seeds
			NostrClient.configuration.relays
		end
	end
end
