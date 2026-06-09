# frozen_string_literal: true

require "test_helper"

module Users
	class RelayListFetchJobTest < ActiveJob::TestCase
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
			event = { "id" => "abc", "pubkey" => pk, "kind" => Events::Kinds::RELAY_LIST }
			fetch_calls = 0
			ingested = []
			Users::RelayListFetch.define_singleton_method(:call) { |**| fetch_calls += 1; event }
			Catalog::Ingest.define_singleton_method(:call) { |event_data:, **| ingested << event_data }

			with_cache do
				Users::RelayListFetchJob.new.perform(pk)
				Users::RelayListFetchJob.new.perform(pk) # within the cooldown
			end

			assert_equal 1, fetch_calls, "the relay round-trip runs once per cooldown window"
			assert_equal [ event ], ingested
		ensure
			Users::RelayListFetch.singleton_class.send(:remove_method, :call)
			Catalog::Ingest.singleton_class.send(:remove_method, :call)
		end

		test "does not ingest when the fetch finds no relay list" do
			pk = SecureRandom.hex(32)
			Users::RelayListFetch.define_singleton_method(:call) { |**| nil }
			ingested = []
			Catalog::Ingest.define_singleton_method(:call) { |**| ingested << :called }

			with_cache { Users::RelayListFetchJob.new.perform(pk) }

			assert_empty ingested
		ensure
			Users::RelayListFetch.singleton_class.send(:remove_method, :call)
			Catalog::Ingest.singleton_class.send(:remove_method, :call)
		end
	end
end
