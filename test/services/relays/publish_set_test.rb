# frozen_string_literal: true

require "test_helper"

module Relays
	# The publish relay set: seeds unioned (additively) with the signed-in user's own NIP-65 WRITE relays.
	class PublishSetTest < ActiveSupport::TestCase
		SEEDS = NostrClient.configuration.relays

		def write_relay(pubkey, url, read: true, write: true)
			UserRelay.create!(pubkey:, url:, read:, write:, relay_list_event_id: "f" * 64, nostr_created_at: Time.current)
		end

		test "a signed-out viewer publishes to the seeds alone" do
			assert_equal SEEDS, Relays::PublishSet.call(user: nil)
		end

		test "a user with no relays falls back to the seeds" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)

			assert_equal SEEDS, Relays::PublishSet.call(user:)
		end

		test "a user's write relays are added on top of the seeds, deduped" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
			write_relay(user.pubkey, "wss://my.relay.test")
			write_relay(user.pubkey, SEEDS.first) # already a seed -> must not duplicate

			result = Relays::PublishSet.call(user:)

			assert_equal SEEDS, result.first(SEEDS.size), "seeds stay present, and lead the list"
			assert_includes result, "wss://my.relay.test"
			assert_equal result.uniq, result, "the seed-overlapping relay appears once (additive union, deduped)"
		end

		test "read-only relays are excluded (only write relays are the outbox)" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
			write_relay(user.pubkey, "wss://write.test", write: true)
			write_relay(user.pubkey, "wss://readonly.test", write: false)

			result = Relays::PublishSet.call(user:)

			assert_includes result, "wss://write.test"
			assert_not_includes result, "wss://readonly.test"
		end
	end
end
