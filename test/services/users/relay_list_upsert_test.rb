# frozen_string_literal: true

require "test_helper"

module Users
	class RelayListUpsertTest < ActiveSupport::TestCase
		R = Events::Kinds::RELAY_LIST

		def r(url, marker = nil) = marker ? [ "r", url, marker ] : [ "r", url ]

		# A faithful kind:10002 winner (raw_event id == event_id, carrying the r-tags), then project it.
		# Deletes any prior kind:10002 for the pubkey first (replaceable: one per pubkey).
		def relay_list(pubkey:, tags:, created_at: Time.current, id: SecureRandom.hex(32))
			Event.where(pubkey:, kind: R).delete_all
			raw = { "id" => id, "pubkey" => pubkey, "created_at" => created_at.to_i, "tags" => tags }
			Event.create!(event_id: id, pubkey:, sig: "f" * 128, kind: R, tags:, nostr_created_at: created_at, raw_event: raw)
			raw
		end

		def project(...) = Users::RelayListUpsert.call(event_data: relay_list(...))

		test "projects write + read rows from r-tags (unmarked = both)" do
			pk = SecureRandom.hex(32)
			project(pubkey: pk, tags: [ r("wss://a.test"), r("wss://b.test", "write"), r("wss://c.test", "read") ])

			rows = UserRelay.where(pubkey: pk)
			both = rows.find_by(url: "wss://a.test")
			write_only = rows.find_by(url: "wss://b.test")
			read_only = rows.find_by(url: "wss://c.test")
			assert both.read && both.write, "unmarked = both"
			assert write_only.write && !write_only.read
			assert read_only.read && !read_only.write
		end

		test "normalizes, dedups, and drops unsafe/invalid urls" do
			pk = SecureRandom.hex(32)
			project(pubkey: pk, tags: [ r("WSS://Relay.TEST/"), r("wss://relay.test"), r("wss://127.0.0.1"), r("nope") ])

			assert_equal [ "wss://relay.test" ], UserRelay.where(pubkey: pk).pluck(:url)
		end

		test "stores every NIP-65 role faithfully -- all unmarked relays are write (the dial cap is not applied here)" do
			pk = SecureRandom.hex(32)
			project(pubkey: pk, tags: (1..5).map { |i| r("wss://w#{i}.test") }) # 5 unmarked (both)

			assert_equal 5, UserRelay.where(pubkey: pk, write: true).count, "unmarked relays are all write-capable"
			assert_equal 5, UserRelay.where(pubkey: pk, read: true).count
		end

		test "rejects an oversized list (projects nothing)" do
			pk = SecureRandom.hex(32)
			project(pubkey: pk, tags: (1..21).map { |i| r("wss://r#{i}.test") })

			assert_equal 0, UserRelay.where(pubkey: pk).count
		end

		test "a newer list replaces the rows wholesale (dropped relays disappear)" do
			pk = SecureRandom.hex(32)
			project(pubkey: pk, tags: [ r("wss://old.test") ], created_at: 1.hour.ago)
			assert_equal [ "wss://old.test" ], UserRelay.where(pubkey: pk).pluck(:url)

			project(pubkey: pk, tags: [ r("wss://new.test") ])
			assert_equal [ "wss://new.test" ], UserRelay.where(pubkey: pk).pluck(:url)
		end

		test "a stale (superseded) list does not overwrite the current projection" do
			pk = SecureRandom.hex(32)
			stale = relay_list(pubkey: pk, tags: [ r("wss://stale.test") ], created_at: 1.hour.ago)
			project(pubkey: pk, tags: [ r("wss://current.test") ]) # deletes the stale event, stores + projects the winner

			Users::RelayListUpsert.call(event_data: stale) # the winner-guard must skip the superseded list

			assert_equal [ "wss://current.test" ], UserRelay.where(pubkey: pk).pluck(:url)
		end
	end
end
