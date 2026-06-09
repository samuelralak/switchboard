# frozen_string_literal: true

require "test_helper"

module Relays
	class DisplayListTest < ActiveSupport::TestCase
		def snapshot_of(map)
			Object.new.tap { |snap| snap.define_singleton_method(:read) { map } }
		end

		def write_relay(pubkey, url, read: true, write: true)
			UserRelay.create!(pubkey:, url:, read:, write:, relay_list_event_id: "f" * 64, nostr_created_at: Time.current)
		end

		test "shows the viewer's own relays with their NIP-65 read/write roles + live status (not the seeds)" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
			write_relay(user.pubkey, "wss://both.test")
			write_relay(user.pubkey, "wss://readonly.test", write: false)

			result = Relays::DisplayList.call(user:, snapshot: snapshot_of({ "wss://both.test" => "connected" }))
			both = result.find { |relay| relay[:host] == "both.test" }
			read_only = result.find { |relay| relay[:host] == "readonly.test" }

			assert_equal %w[both.test readonly.test], result.pluck(:host).sort
			assert both[:read] && both[:write], "unmarked relay is read + write"
			assert read_only[:read] && !read_only[:write], "read-marked relay is read-only"
			assert_equal :live, both[:status]
			assert_not_includes result.pluck(:host), "relay.damus.io", "seeds are not mixed into a user's own list"
		end

		test "keeps relays on the same host but different paths distinct (no collapsed duplicate)" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
			write_relay(user.pubkey, "wss://shared.test", write: false)
			write_relay(user.pubkey, "wss://shared.test/inbox", write: false)

			hosts = Relays::DisplayList.call(user:, snapshot: snapshot_of({})).pluck(:host)

			assert_includes hosts, "shared.test"
			assert_includes hosts, "shared.test/inbox"
		end

		test "falls back to the seeds (read + write defaults, all settled) for a signed-out viewer" do
			seeds = NostrClient.configuration.relays.map { |url| url.sub(%r{\Awss?://}, "") }

			result = Relays::DisplayList.call(user: nil, snapshot: snapshot_of({}))

			assert_equal seeds.sort, result.pluck(:host).sort
			assert(result.all? { |relay| relay[:read] && relay[:write] }, "seeds are general-purpose defaults")
			assert(result.all? { |relay| relay[:status] == :settled })
		end
	end
end
