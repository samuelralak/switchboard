# frozen_string_literal: true

require "test_helper"

module Relays
	class DesiredSetTest < ActiveSupport::TestCase
		def active_user(pubkey: SecureRandom.hex(32))
			user = User.create!(pubkey:, first_seen_at: Time.current)
			Session.create!(user:) # fresh session => active
			user
		end

		def write_relay(pubkey:, url:, write: true, read: true)
			UserRelay.create!(pubkey:, url:, write:, read:, relay_list_event_id: "f" * 64, nostr_created_at: Time.current)
		end

		test "combines seeds with active users' write relays, coverage-ranked and ceiling-capped" do
			u1 = active_user
			u2 = active_user
			write_relay(pubkey: u1.pubkey, url: "wss://popular.test") # covered by 2 users
			write_relay(pubkey: u2.pubkey, url: "wss://popular.test")
			write_relay(pubkey: u1.pubkey, url: "wss://solo.test")    # covered by 1, cut by the ceiling

			result = Relays::DesiredSet.call(seeds: [ "wss://seed.test" ], ceiling: 1)

			assert_includes result, "wss://seed.test", "seeds are always included"
			assert_includes result, "wss://popular.test", "the most-covered user relay wins the budget"
			assert_not_includes result, "wss://solo.test", "the ceiling caps user relays"
		end

		test "excludes write relays of users with no active session" do
			dormant = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
			Session.create!(user: dormant, created_at: 31.days.ago) # an expired session (Rails keeps a given created_at)
			write_relay(pubkey: dormant.pubkey, url: "wss://dormant.test")

			assert_not_includes Relays::DesiredSet.call(seeds: []), "wss://dormant.test"
		end

		test "excludes read-only relays (the ingest reads from write relays only)" do
			user = active_user
			write_relay(pubkey: user.pubkey, url: "wss://readonly.test", write: false, read: true)

			assert_not_includes Relays::DesiredSet.call(seeds: []), "wss://readonly.test"
		end

		test "dials at most max_write_relays_per_user of a single user's write relays" do
			user = active_user
			cap = NostrClient.configuration.max_write_relays_per_user
			(1..(cap + 2)).each { |i| write_relay(pubkey: user.pubkey, url: "wss://w#{i}.test") }

			dialed = Relays::DesiredSet.call(seeds: []) & (1..(cap + 2)).map { |i| "wss://w#{i}.test" }

			assert_equal cap, dialed.size, "the per-user dial cap bounds one user's contribution, not the full stored list"
		end
	end
end
