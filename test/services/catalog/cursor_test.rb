# frozen_string_literal: true

require "test_helper"

module Catalog
	class CursorTest < ActiveSupport::TestCase
		# Inject a real MemoryStore (test env is :null_store) so since/advance actually round-trip.
		setup { @cursor = Catalog::Cursor.new(store: ActiveSupport::Cache::MemoryStore.new) }

		test "since is nil until something is ingested" do
			assert_nil @cursor.since
		end

		test "advance sets the high-water-mark and since subtracts the overlap" do
			@cursor.advance(1_700_000_000)

			assert_equal 1_700_000_000 - Catalog::Cursor::OVERLAP, @cursor.since
		end

		test "advance does not move the high-water-mark backward for an older event" do
			@cursor.advance(1_700_000_000)
			@cursor.advance(1_600_000_000)

			assert_equal 1_700_000_000 - Catalog::Cursor::OVERLAP, @cursor.since
		end

		test "advance ignores a nil created_at" do
			@cursor.advance(nil)

			assert_nil @cursor.since
		end
	end
end
