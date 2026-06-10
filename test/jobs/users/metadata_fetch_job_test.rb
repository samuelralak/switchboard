# frozen_string_literal: true

require "test_helper"

module Users
	class MetadataFetchJobTest < ActiveJob::TestCase
		# Point Rails.cache at a real MemoryStore (test env is :null_store) so the cooldown actually caches.
		def with_cache
			cache = ActiveSupport::Cache::MemoryStore.new
			original = Rails.method(:cache)
			Rails.define_singleton_method(:cache) { cache }
			yield
		ensure
			Rails.define_singleton_method(:cache, original)
		end

		test "fetches once per cooldown window and ingests the result" do
			pk = SecureRandom.hex(32)
			event = { "id" => "abc", "pubkey" => pk, "kind" => Events::Kinds::METADATA }
			fetch_calls = 0
			ingested = []
			Users::MetadataFetch.define_singleton_method(:call) { |**| fetch_calls += 1; event }
			Catalog::Ingest.define_singleton_method(:call) { |event_data:, **| ingested << event_data }

			with_cache do
				Users::MetadataFetchJob.new.perform(pk)
				Users::MetadataFetchJob.new.perform(pk) # within the cooldown
			end

			assert_equal 1, fetch_calls, "the relay round-trip runs once per cooldown window"
			assert_equal [ event ], ingested
		ensure
			Users::MetadataFetch.singleton_class.send(:remove_method, :call)
			Catalog::Ingest.singleton_class.send(:remove_method, :call)
		end

		test "force: true bypasses the cooldown to re-fetch after a profile edit" do
			pk = SecureRandom.hex(32)
			event = { "id" => "abc", "pubkey" => pk, "kind" => Events::Kinds::METADATA }
			fetch_calls = 0
			Users::MetadataFetch.define_singleton_method(:call) { |**| fetch_calls += 1; event }
			Catalog::Ingest.define_singleton_method(:call) { |**| nil }

			with_cache do
				Users::MetadataFetchJob.new.perform(pk)
				Users::MetadataFetchJob.new.perform(pk, force: true) # the post-edit refresh
			end

			assert_equal 2, fetch_calls, "force re-runs the fetch within the cooldown window"
		ensure
			Users::MetadataFetch.singleton_class.send(:remove_method, :call)
			Catalog::Ingest.singleton_class.send(:remove_method, :call)
		end

		test "does not ingest when the fetch finds no metadata" do
			pk = SecureRandom.hex(32)
			Users::MetadataFetch.define_singleton_method(:call) { |**| nil }
			ingested = []
			Catalog::Ingest.define_singleton_method(:call) { |**| ingested << :called }

			with_cache { Users::MetadataFetchJob.new.perform(pk) }

			assert_empty ingested
		ensure
			Users::MetadataFetch.singleton_class.send(:remove_method, :call)
			Catalog::Ingest.singleton_class.send(:remove_method, :call)
		end
	end
end
