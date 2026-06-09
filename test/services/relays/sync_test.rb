# frozen_string_literal: true

require "test_helper"

module Relays
	class SyncTest < ActiveSupport::TestCase
		def connection(url: "wss://r.test")
			Object.new.tap { |c| c.define_singleton_method(:url) { url } }
		end

		def find_only(spec)
			Object.new.tap { |r| r.define_singleton_method(:find) { |_id| spec } }
		end

		# Spy on Rails.application.executor.wrap so a test can assert reactor-thread DB work is wrapped. Yields
		# the block (so the wrapped enqueue still runs) and records each invocation; restored after.
		def with_executor_spy
			executor = Rails.application.executor
			invocations = []
			executor.define_singleton_method(:wrap) { |*, **, &block| invocations << true; block&.call }
			yield invocations
		ensure
			executor.singleton_class.send(:remove_method, :wrap)
		end

		# Point Rails.cache at a real MemoryStore (test env is :null_store) so the status snapshot persists.
		def with_cache
			cache = ActiveSupport::Cache::MemoryStore.new
			original = Rails.method(:cache)
			Rails.define_singleton_method(:cache) { cache }
			yield
		ensure
			Rails.define_singleton_method(:cache, original)
		end

		test "reconcile writes the live status snapshot (for the web UI) after reconciling" do
			manager = Object.new
			manager.define_singleton_method(:status) do
				{ "wss://a.test" => { state: :connected, subscriptions: [ "listings" ], reconnect_attempts: 0 } }
			end
			Relays::Reconcile.define_singleton_method(:call) { |**| nil }

			with_cache do
				Relays::Sync.new(manager:).send(:reconcile)

				assert_equal({ "wss://a.test" => "connected" }, Relays::StatusSnapshot.new.read)
			end
		ensure
			Relays::Reconcile.singleton_class.send(:remove_method, :call)
		end

		test "dispatch routes an event to its subscription's ingest by subscription_id" do
			enqueued = []
			ingest = Object.new
			ingest.define_singleton_method(:perform_later) { |json, url| enqueued << [ json, url ] }
			spec = Relays::Subscription.new(id: "listings", kinds: [ 30_402 ], ingest:)
			registry = Object.new
			registry.define_singleton_method(:find) { |id| id == "listings" ? spec : nil }
			sync = Relays::Sync.new(registry:, manager: Object.new)

			sync.send(:dispatch, connection(url: "wss://a.test"), "listings", { "id" => "e1" })

			assert_equal [ [ "{\"id\":\"e1\"}", "wss://a.test" ] ], enqueued
		end

		test "dispatch enqueues inside the Rails executor (reactor-thread DB safety)" do
			enqueued = []
			ingest = Object.new
			ingest.define_singleton_method(:perform_later) { |*args| enqueued << args }
			spec = Relays::Subscription.new(id: "listings", kinds: [ 30_402 ], ingest:)
			sync = Relays::Sync.new(registry: find_only(spec), manager: Object.new)

			with_executor_spy do |invocations|
				sync.send(:dispatch, connection, "listings", { "id" => "e1" })

				assert_equal 1, invocations.size, "the enqueue must run wrapped in the Rails executor"
			end

			assert_equal 1, enqueued.size, "and the wrapped block still enqueues the ingest"
		end

		test "dispatch swallows and logs an ingest error rather than raising out (the reactor must survive)" do
			ingest = Object.new
			ingest.define_singleton_method(:perform_later) { |*| raise "boom" }
			spec = Relays::Subscription.new(id: "listings", kinds: [ 1 ], ingest:)
			sync = Relays::Sync.new(registry: find_only(spec), manager: Object.new)

			assert_nothing_raised { sync.send(:dispatch, connection, "listings", { "id" => "e1" }) }
		end

		test "dispatch ignores an event whose subscription_id is not registered" do
			registry = Object.new
			registry.define_singleton_method(:find) { |_id| nil }
			sync = Relays::Sync.new(registry:, manager: Object.new)

			assert_nothing_raised { sync.send(:dispatch, connection, "ghost", { "id" => "e1" }) }
		end

		test "subscribe registers every spec's live filters with the manager" do
			calls = []
			manager = Object.new
			manager.define_singleton_method(:subscribe_all) { |id, filters| calls << [ id, filters ] }
			spec = Relays::Subscription.new(id: "listings", kinds: [ 30_402 ], ingest: nil, limit: 25)
			registry = Object.new
			registry.define_singleton_method(:all) { [ spec ] }

			Relays::Sync.new(registry:, manager:).send(:subscribe)

			assert_equal [ [ "listings", [ { kinds: [ 30_402 ], limit: 25 } ] ] ], calls
		end
	end
end
