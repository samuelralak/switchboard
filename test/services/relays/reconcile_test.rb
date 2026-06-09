# frozen_string_literal: true

require "test_helper"

module Relays
	class ReconcileTest < ActiveJob::TestCase
		test "opens desired relays not already connected and backfills each registered subscription (add-only)" do
			added = []
			manager = Object.new
			manager.define_singleton_method(:connection_urls) { [ "wss://open.test" ] }
			manager.define_singleton_method(:add_connection) { |url| added << url }
			registry = Object.new
			registry.define_singleton_method(:all) { [ Relays::Subscription.new(id: "listings", kinds: [ 30_402 ], ingest: Catalog::IngestJob) ] }
			Relays::DesiredSet.define_singleton_method(:call) { |**| [ "wss://open.test", "wss://new.test" ] }

			assert_enqueued_with(job: Relays::BackfillJob, args: [ "wss://new.test", "listings" ]) do
				Relays::Reconcile.call(manager:, registry:)
			end

			assert_equal [ "wss://new.test" ], added, "an already-open relay is not re-added; a newly-desired one is"
		ensure
			Relays::DesiredSet.singleton_class.send(:remove_method, :call)
		end

		# A manager double that records evictions and never re-adds; seed.test/stale.test stay "open".
		def evicting_manager(removed, open:)
			Object.new.tap do |manager|
				manager.define_singleton_method(:connection_urls) { open }
				manager.define_singleton_method(:add_connection) { |_url| nil }
				manager.define_singleton_method(:remove_connection) { |url| removed << url }
			end
		end

		def empty_registry = Object.new.tap { |r| r.define_singleton_method(:all) { [] } }

		test "evicts an undesired relay only after TEARDOWN_GRACE consecutive ticks; never the seed" do
			removed = []
			manager = evicting_manager(removed, open: [ "wss://stale.test", "wss://seed.test" ])
			store = ActiveSupport::Cache::MemoryStore.new
			Relays::DesiredSet.define_singleton_method(:call) { |**| [ "wss://seed.test" ] } # stale.test is undesired

			Relays::Reconcile.call(manager:, registry: empty_registry, store:)
			assert_empty removed, "tick 1: counted, not yet evicted"

			Relays::Reconcile.call(manager:, registry: empty_registry, store:)
			assert_equal [ "wss://stale.test" ], removed, "tick 2 (>= grace): evicted; the always-desired seed is untouched"
		ensure
			Relays::DesiredSet.singleton_class.send(:remove_method, :call)
		end

		test "resets the eviction countdown when a relay re-enters the desired set (consecutive, not cumulative)" do
			removed = []
			manager = evicting_manager(removed, open: [ "wss://stale.test" ])
			store = ActiveSupport::Cache::MemoryStore.new
			undesired = -> { Relays::DesiredSet.define_singleton_method(:call) { |**| [] } }
			desired = -> { Relays::DesiredSet.define_singleton_method(:call) { |**| [ "wss://stale.test" ] } }

			undesired.call
			Relays::Reconcile.call(manager:, registry: empty_registry, store:) # count 1
			desired.call
			Relays::Reconcile.call(manager:, registry: empty_registry, store:) # re-desired => reset
			undesired.call
			Relays::Reconcile.call(manager:, registry: empty_registry, store:) # count 1 again, not 2

			assert_empty removed, "a relay that flaps back to desired never reaches the consecutive grace"
		ensure
			Relays::DesiredSet.singleton_class.send(:remove_method, :call)
		end
	end
end
