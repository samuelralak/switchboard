# frozen_string_literal: true

require "test_helper"

module Catalog
	class SyncTest < ActiveSupport::TestCase
		def cursor = Catalog::Cursor.new(store: ActiveSupport::Cache::MemoryStore.new)

		test "catalog_filters carries no since on a first-ever boot (full initial pull)" do
			filter = Catalog::Sync.new(limit: 25, cursor:).send(:catalog_filters).first

			assert_equal [ Events::Kinds::CLASSIFIED ], filter[:kinds]
			assert_equal 25, filter[:limit]
			assert_not filter.key?(:since)
		end

		test "catalog_filters resumes from the cursor with the overlap subtracted" do
			resumed = cursor
			resumed.advance(1_700_000_000)
			filter = Catalog::Sync.new(limit: 25, cursor: resumed).send(:catalog_filters).first

			assert_equal 1_700_000_000 - Catalog::Cursor::OVERLAP, filter[:since]
		end
	end
end
