# frozen_string_literal: true

require "test_helper"

module Relays
	class BackfillJobTest < ActiveJob::TestCase
		setup { Relays::Registry.instance.clear }
		teardown { Relays::Registry.instance.clear }

		# Point Rails.cache at a real MemoryStore (test env is :null_store) so the once-per-url flag caches.
		def with_cache
			cache = ActiveSupport::Cache::MemoryStore.new
			original = Rails.method(:cache)
			Rails.define_singleton_method(:cache) { cache }
			yield
		ensure
			Rails.define_singleton_method(:cache, original)
		end

		def register(id: "listings", ingest: Catalog::IngestJob)
			Relays::Registry.instance.register(Relays::Subscription.new(id:, kinds: [ 30_402 ], ingest:))
		end

		test "backfills a relay once per subscription, enqueuing the spec's ingest per event, then skips within the flag" do
			url = "wss://new.test"
			events = [ { "id" => "a" }, { "id" => "b" } ]
			fetch_calls = 0
			Relays::FetchEvents.define_singleton_method(:call) { |**| fetch_calls += 1; events }
			register

			with_cache do
				assert_enqueued_jobs 2, only: Catalog::IngestJob do
					Relays::BackfillJob.new.perform(url, "listings")
				end
				assert_no_enqueued_jobs only: Catalog::IngestJob do
					Relays::BackfillJob.new.perform(url, "listings") # within the once-per-(sub,url) flag window
				end
			end

			assert_equal 1, fetch_calls, "the relay backlog is pulled exactly once per (subscription, url)"
		ensure
			Relays::FetchEvents.singleton_class.send(:remove_method, :call)
		end

		test "isolates the backfill flag per subscription, so a second consumer on the same url still pulls" do
			url = "wss://shared.test"
			fetch_calls = 0
			Relays::FetchEvents.define_singleton_method(:call) { |**| fetch_calls += 1; [] }
			register(id: "listings")
			register(id: "notes")

			with_cache do
				Relays::BackfillJob.new.perform(url, "listings")
				Relays::BackfillJob.new.perform(url, "notes")
			end

			assert_equal 2, fetch_calls, "a different subscription on the same url is not blocked by the flag"
		ensure
			Relays::FetchEvents.singleton_class.send(:remove_method, :call)
		end

		test "no-ops when the subscription_id is not registered" do
			ran = false
			Relays::FetchEvents.define_singleton_method(:call) { |**| ran = true; [] }

			with_cache { Relays::BackfillJob.new.perform("wss://x.test", "ghost") }

			assert_not ran, "an unregistered subscription_id pulls nothing"
		ensure
			Relays::FetchEvents.singleton_class.send(:remove_method, :call)
		end
	end
end
