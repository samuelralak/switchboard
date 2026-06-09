# frozen_string_literal: true

require "test_helper"

module Catalog
	class IngestJobTest < ActiveJob::TestCase
		setup { @cache = ActiveSupport::Cache::MemoryStore.new }

		# Point Rails.cache at the MemoryStore for the block (test env is :null_store), restoring after.
		def with_cache
			cache = @cache
			original = Rails.method(:cache)
			Rails.define_singleton_method(:cache) { cache }
			yield
		ensure
			Rails.define_singleton_method(:cache, original)
		end

		# Swap Catalog::Ingest.call for the block so the job can be driven without a fully-signed event.
		def stub_ingest(result)
			original = Catalog::Ingest.method(:call)
			Catalog::Ingest.define_singleton_method(:call) { |**| result }
			yield
		ensure
			Catalog::Ingest.define_singleton_method(:call, original)
		end

		test "advances the ingest cursor to the stored event's created_at" do
			with_cache do
				stub_ingest(Event.new) do
					Catalog::IngestJob.new.perform({ "id" => "x", "created_at" => 1_700_000_000 }.to_json)
				end

				assert_equal 1_700_000_000 - Catalog::Cursor::OVERLAP, Catalog::Cursor.new.since
			end
		end

		test "does not advance the cursor when nothing was stored (duplicate / ephemeral)" do
			with_cache do
				stub_ingest(:duplicate) do
					Catalog::IngestJob.new.perform({ "id" => "x", "created_at" => 1_700_000_000 }.to_json)
				end

				assert_nil Catalog::Cursor.new.since
			end
		end
	end
end
