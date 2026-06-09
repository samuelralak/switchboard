# frozen_string_literal: true

require "test_helper"

module Relays
	class StatusSnapshotTest < ActiveSupport::TestCase
		def snapshot = Relays::StatusSnapshot.new(store: ActiveSupport::Cache::MemoryStore.new)

		# One Manager#status entry; only :state survives into the snapshot.
		def entry(state) = { state:, subscriptions: [ "listings" ], reconnect_attempts: 0 }

		test "write reduces Manager#status to url => state-as-string, and read returns it" do
			snap = snapshot
			snap.write({ "wss://a.test" => entry(:connected), "wss://b.test" => entry(:connecting) })

			assert_equal({ "wss://a.test" => "connected", "wss://b.test" => "connecting" }, snap.read)
		end

		test "read returns an empty hash on a cold cache" do
			assert_equal({}, snapshot.read)
		end
	end
end
