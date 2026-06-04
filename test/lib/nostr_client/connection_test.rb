# frozen_string_literal: true

require "test_helper"

module NostrClient
	class ConnectionTest < ActiveSupport::TestCase
		# A pending entry now carries the queue and the original event (for auth-required re-send).
		def pending_entry(id) = { queue: Thread::Queue.new, event: { "id" => id } }

		test "does not reconnect after a deliberate stop" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })

			connection.disconnect # marks stopping and returns early (it never connected)
			connection.send(:schedule_reconnect)

			assert_equal 0, connection.reconnect_attempts
		end

		test "schedules a reconnect after an unexpected drop" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			scheduled = false
			connection.define_singleton_method(:schedule_reconnect) { scheduled = true }

			connection.send(:on_close, Struct.new(:code).new(1006))

			assert scheduled
		end

		test "publish returns an error result when not connected" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			result = connection.publish("id" => "abc")

			assert_not result.ok?
			assert_equal :error, result.status
		end

		test "settle_ok resolves a pending publish as accepted" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			entry = pending_entry("evt1")
			connection.send(:pending)["evt1"] = entry

			connection.settle_ok("evt1", true, "")

			assert entry[:queue].pop.ok?
		end

		test "settle_ok resolves a rejected publish with the relay's message" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			entry = pending_entry("evt1")
			connection.send(:pending)["evt1"] = entry

			connection.settle_ok("evt1", false, "blocked: spam")
			result = entry[:queue].pop

			assert_not result.ok?
			assert_equal :rejected, result.status
			assert_equal "blocked: spam", result.message
		end

		test "a publish that is accepted but never returns OK settles as :timeout" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			entry = pending_entry("evt1")
			connection.send(:pending)["evt1"] = entry

			connection.send(:settle, "evt1", status: :timeout, message: nil)

			assert_equal :timeout, entry[:queue].pop.status
		end

		test "settle is idempotent: a second OK after the first is a no-op" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			entry = pending_entry("evt1")
			connection.send(:pending)["evt1"] = entry

			connection.settle_ok("evt1", true, "")
			assert_equal :ok, entry[:queue].pop.status
			connection.settle_ok("evt1", false, "blocked: late") # entry already gone

			assert connection.send(:pending).empty?
			assert entry[:queue].empty?, "no second result is pushed"
		end

		test "a relay close fails every in-flight publish, not just one" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			connection.define_singleton_method(:schedule_reconnect) { nil }
			one = pending_entry("evt1")
			two = pending_entry("evt2")
			connection.send(:pending)["evt1"] = one
			connection.send(:pending)["evt2"] = two

			connection.send(:on_close, Struct.new(:code).new(1006))

			assert_equal :error, one[:queue].pop.status
			assert_equal :error, two[:queue].pop.status
		end

		test "a relay close resets the AUTH challenge and attempt counter" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			connection.define_singleton_method(:schedule_reconnect) { nil }
			connection.store_challenge("chal")
			connection.instance_variable_set(:@auth_attempts, 2)

			connection.send(:on_close, Struct.new(:code).new(1006))

			assert_nil connection.challenge
			assert_equal 0, connection.send(:auth_attempts)
		end

		test "a duplicate in-flight publish id fails fast instead of orphaning the first caller" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			first = Thread::Queue.new
			connection.send(:pending)["evt1"] = { queue: first, event: { "id" => "evt1" } }
			second = Thread::Queue.new

			connection.send(:register_and_send, "evt1", second, { "id" => "evt1" })

			result = second.pop
			assert_equal :error, result.status
			assert_equal "duplicate in-flight publish", result.message
			assert first.empty?, "the first caller stays in-flight, not orphaned"
		end

		test "drop_subscription sends a NIP-01 CLOSE and forgets the subscription" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			sent = []
			connection.define_singleton_method(:send_frame) { |*frame| sent << frame }
			connection.subscribe("sub1", [ { kinds: [ 1 ] } ])

			connection.drop_subscription("sub1")

			assert_includes sent, [ NostrClient::Messages::Outbound::CLOSE, "sub1" ]
			assert_not_includes connection.subscriptions.keys, "sub1"
		end
	end
end
