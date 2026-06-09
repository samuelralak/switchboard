# frozen_string_literal: true

require "test_helper"

module Relays
	class SubscriptionTest < ActiveSupport::TestCase
		def spec(cursor: nil, limit: 25)
			Relays::Subscription.new(id: "s", kinds: [ 30_402 ], ingest: nil, cursor:, limit:)
		end

		def cursor_returning(since)
			Object.new.tap { |c| c.define_singleton_method(:since) { since } }
		end

		test "live_filters carries kinds + limit and no since without a cursor" do
			filter = spec.live_filters.first

			assert_equal [ 30_402 ], filter[:kinds]
			assert_equal 25, filter[:limit]
			assert_not filter.key?(:since)
		end

		test "live_filters resumes from the cursor's since" do
			assert_equal 1_700_000_000, spec(cursor: cursor_returning(1_700_000_000)).live_filters.first[:since]
		end

		test "live_filters omits since when the cursor has none (first-ever boot)" do
			assert_not spec(cursor: cursor_returning(nil)).live_filters.first.key?(:since)
		end

		test "backfill_filters carries the standalone backfill limit (independent of the live limit) and no since" do
			filter = spec(limit: 25).backfill_filters.first

			assert_equal NostrClient.configuration.backfill_limit, filter[:limit]
			assert_not filter.key?(:since)
		end

		test "enqueue hands the ingest job the event json and source url" do
			calls = []
			ingest = Object.new
			ingest.define_singleton_method(:perform_later) { |json, url| calls << [ json, url ] }
			Relays::Subscription.new(id: "s", kinds: [ 1 ], ingest:).enqueue({ "id" => "e1" }, "wss://r.test")

			assert_equal [ [ "{\"id\":\"e1\"}", "wss://r.test" ] ], calls
		end
	end
end
