# frozen_string_literal: true

module Profiles
	# The command half of the profile page: resolves the npub URL to an identity for viewing, then hands off to
	# the pure render-state builder. A malformed npub is a missing resource (raise -> Rails 404). A valid but
	# not-yet-projected pubkey lazily enqueues a kind-0 fetch -- cooldown-throttled, NO force, since this is an
	# anonymous, refresh-on-every-load read path (force is only for the user's own post-edit refetch) -- so the
	# profile hydrates in the background while the placeholder renders. Enqueuing from a read path mirrors
	# Sessions::Authenticate / Events::Upsert. Keeping the raise + enqueue here leaves the controller a one-liner
	# and Ui::State a pure builder.
	class Resolve < BaseService
		option :npub, type: Types::Strict::String
		option :viewer

		def call
			pubkey = User.pubkey_from_npub(npub) or raise ActiveRecord::RecordNotFound

			user = User.find_by(pubkey:)
			enqueue_fetch(pubkey) unless user

			Ui::State.portfolio(pubkey:, user:, owner: viewer&.pubkey == pubkey)
		end

		private

		# Lazy kind-0 fetch on a miss, throttled per pubkey: an anonymous viewer refreshing /u/:npub (or
		# fanning across many unprojected npubs) must not enqueue a relay-fetch job on every load. unless_exist
		# returns true only on the first write in the window, so we enqueue once and skip until it expires.
		def enqueue_fetch(pubkey)
			key = "profiles:fetch_enqueued:#{pubkey}"
			fresh = Rails.cache.write(key, true, expires_in: 10.minutes, unless_exist: true)

			Users::MetadataFetchJob.perform_later(pubkey) if fresh
		end
	end
end
