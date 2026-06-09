# frozen_string_literal: true

require "test_helper"

module Catalog
	class RelaySubscriptionTest < ActiveSupport::TestCase
		def cursor = Catalog::Cursor.new(store: ActiveSupport::Cache::MemoryStore.new)

		test "builds the catalog's listings subscription (kind 30402, ingested by IngestJob)" do
			subscription = Catalog::RelaySubscription.call

			assert_equal "listings", subscription.id
			assert_equal [ Events::Kinds::CLASSIFIED ], subscription.kinds
			assert_equal Catalog::IngestJob, subscription.ingest
			assert_equal 500, subscription.live_filters.first[:limit]
		end

		test "resumes the live filter from the injected cursor's high-water-mark (overlap subtracted)" do
			resumed = cursor
			resumed.advance(1_700_000_000)

			filter = Catalog::RelaySubscription.call(cursor: resumed).live_filters.first

			assert_equal 1_700_000_000 - Catalog::Cursor::OVERLAP, filter[:since]
		end

		test "carries no since on a first-ever boot (empty cursor)" do
			assert_not Catalog::RelaySubscription.call(cursor:).live_filters.first.key?(:since)
		end
	end
end
