# frozen_string_literal: true

require "test_helper"

module Relays
	class FetchEventsTest < ActiveSupport::TestCase
		def event(id: SecureRandom.hex(32)) = { "id" => id, "kind" => 30_402 }

		# A fetch with its reactor boot + socket I/O stubbed: each relay synchronously feeds its canned frames.
		def stubbed(feed:, timeout: 1)
			fetch = Relays::FetchEvents.new(relays: feed.keys, filters: [ { kinds: [ 30_402 ] } ], timeout:)
			fetch.define_singleton_method(:boot) { nil }
			fetch.define_singleton_method(:open_connection) do |url, inbox|
				collector = send(:collector_for, url, inbox)
				feed.fetch(url).each { |ev| collector.call(nil, [ "EVENT", "s", ev ]) }
				collector.call(nil, [ "EOSE", url ])
				Object.new.tap { |c| c.define_singleton_method(:disconnect) { nil } }
			end
			fetch
		end

		test "collects every event across relays (unfiltered) until each EOSEs" do
			a1 = event
			a2 = event
			b1 = event
			feed = { "wss://a.test" => [ a1, a2 ], "wss://b.test" => [ b1 ] }

			ids = stubbed(feed:).call.pluck("id")

			assert_equal [ a1["id"], a2["id"], b1["id"] ].sort, ids.sort
		end

		test "returns what arrived before the timeout when a relay never EOSEs" do
			fetch = Relays::FetchEvents.new(relays: [ "wss://slow.test" ], filters: [ {} ], timeout: 0.2)
			fetch.define_singleton_method(:boot) { nil }
			fetch.define_singleton_method(:open_connection) do |_url, _inbox|
				Object.new.tap { |c| c.define_singleton_method(:disconnect) { nil } }
			end

			assert_empty fetch.call
		end

		test "returns [] and does not boot when no relays are given" do
			booted = false
			fetch = Relays::FetchEvents.new(relays: [], filters: [ {} ])
			fetch.define_singleton_method(:boot) { booted = true }

			assert_empty fetch.call
			assert_not booted
		end
	end
end
