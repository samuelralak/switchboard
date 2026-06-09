# frozen_string_literal: true

require "test_helper"

module NostrClient
	class ConnectionTest < ActiveSupport::TestCase
		# A pending entry now carries the queue and the original event (for auth-required re-send).
		def pending_entry(id) = { queue: Thread::Queue.new, event: { "id" => id } }

		# Swap EventMachine module methods for the duration of a block (no live reactor), restoring after.
		def with_em(stubs)
			originals = stubs.keys.index_with { |name| EventMachine.method(name) }
			stubs.each { |name, impl| EventMachine.define_singleton_method(name, &impl) }
			yield
		ensure
			originals.each { |name, method| EventMachine.define_singleton_method(name, method) }
		end

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

		# --- reconnect-forever backoff (a relay is never permanently abandoned) ---

		test "a reconnect is still scheduled well past the old attempt cap" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			cap = NostrClient.configuration.max_reconnect_attempts
			connection.instance_variable_set(:@reconnect_attempts, cap + 5)
			armed = []

			with_em(add_timer: ->(delay, &_b) { armed << delay }) do
				connection.send(:schedule_reconnect)
			end

			assert_equal 1, armed.size, "the relay is not abandoned past the cap"
		end

		test "reconnect delay grows to the ceiling and carries jitter" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			max = NostrClient.configuration.max_reconnect_delay_seconds
			connection.instance_variable_set(:@reconnect_attempts, 50) # deep into backoff: at the ceiling

			first = connection.send(:reconnect_delay)
			second = connection.send(:reconnect_delay)

			assert_operator first, :>=, max
			assert_operator first, :<=, max * (1 + NostrClient::Connection::JITTER_FRACTION)
			assert_not_equal first, second, "jitter de-syncs reconnects"
		end

		test "on_open records the open time and does NOT reset the backoff on the bare upgrade" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.define_singleton_method(:resubscribe) { nil }
			connection.define_singleton_method(:start_keepalive) { nil }
			connection.instance_variable_set(:@reconnect_attempts, 7)

			connection.send(:on_open)

			assert connection.instance_variable_get(:@opened_at), "records open time for the stability check"
			assert_equal 7, connection.reconnect_attempts, "backoff clears only once the link proves stable"
		end

		test "backoff resets after a stable connection closes, but not after a handshake-then-close" do
			interval = NostrClient.configuration.ping_interval_seconds

			stable = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			stable.define_singleton_method(:schedule_reconnect) { nil }
			stable.send(:transition_to, :connected)
			stable.instance_variable_set(:@reconnect_attempts, 6)
			stable.instance_variable_set(:@opened_at, Process.clock_gettime(Process::CLOCK_MONOTONIC) - (interval + 10))
			stable.send(:on_close, Struct.new(:code).new(1006))
			assert_equal 0, stable.reconnect_attempts, "a connection that stayed up clears its backoff"

			flapping = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			flapping.define_singleton_method(:schedule_reconnect) { nil }
			flapping.send(:transition_to, :connected)
			flapping.instance_variable_set(:@reconnect_attempts, 6)
			flapping.instance_variable_set(:@opened_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
			flapping.send(:on_close, Struct.new(:code).new(1006))
			assert_equal 6, flapping.reconnect_attempts, "a handshake-then-close keeps escalating its backoff"
		end

		test "a single degraded WARN is logged as reconnects cross the cap" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			cap = NostrClient.configuration.max_reconnect_attempts
			connection.instance_variable_set(:@reconnect_attempts, cap)
			io = StringIO.new
			original = Rails.logger
			Rails.logger = ActiveSupport::Logger.new(io)

			with_em(add_timer: ->(*_a, &_b) { }) do
				connection.send(:schedule_reconnect) # -> cap+1: WARN
				connection.send(:schedule_reconnect) # -> cap+2: no WARN
			end

			assert_equal 1, io.string.scan("degraded").size
		ensure
			Rails.logger = original
		end

		# --- keepalive / half-open detection ---

		test "on_open arms a keepalive ping timer and on_close cancels it" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.define_singleton_method(:resubscribe) { nil }
			connection.define_singleton_method(:schedule_reconnect) { nil }
			canceled = []

			with_em(add_periodic_timer: ->(_i, &_b) { :ping_timer }, cancel_timer: ->(timer) { canceled << timer }) do
				connection.send(:on_open)
				assert_equal :ping_timer, connection.instance_variable_get(:@ping_timer)

				connection.send(:on_close, Struct.new(:code).new(1006))
				assert_includes canceled, :ping_timer
				assert_nil connection.instance_variable_get(:@ping_timer)
			end
		end

		test "a missing PONG within the timeout force-closes the socket so on_close reconnects" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			closed = false
			socket = Object.new
			socket.define_singleton_method(:ping) { |&_blk| true } # truthy: ping sent, but PONG never returns
			socket.define_singleton_method(:close) { closed = true }
			connection.instance_variable_set(:@socket, socket)
			deadline_block = nil

			with_em(add_timer: ->(_t, &blk) { deadline_block = blk; :deadline }, cancel_timer: ->(_t) { }) do
				connection.send(:send_ping)
			end
			deadline_block.call # the pong-timeout fires

			assert closed, "a half-open socket is force-closed when no PONG returns"
		end

		test "a second ping while a PONG is outstanding arms no new deadline (no overlap / no timer leak)" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			socket = Object.new
			socket.define_singleton_method(:ping) { |&_b| true } # ping sent, PONG not yet returned
			socket.define_singleton_method(:close) { nil }
			connection.instance_variable_set(:@socket, socket)
			armed = 0

			with_em(add_timer: ->(_t, &_b) { armed += 1; :deadline }, cancel_timer: ->(_t) { }) do
				connection.send(:send_ping)
				connection.send(:send_ping) # @pong_deadline still set: the no-overlap guard makes this a no-op
			end

			assert_equal 1, armed, "the second ping arms no new pong deadline"
		end

		test "send_ping clears the pong deadline when ping returns false (socket past OPEN)" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			socket = Object.new
			socket.define_singleton_method(:ping) { |&_b| false } # socket past OPEN: no PONG will arrive
			socket.define_singleton_method(:close) { nil }
			connection.instance_variable_set(:@socket, socket)
			canceled = 0

			with_em(add_timer: ->(_t, &_b) { :deadline }, cancel_timer: ->(_t) { canceled += 1 }) do
				connection.send(:send_ping)
			end

			assert_equal 1, canceled, "the just-armed deadline is cancelled when the ping cannot be sent"
			assert_nil connection.instance_variable_get(:@pong_deadline)
		end

		test "re-arming a publish timeout cancels the prior EM timer before arming the fresh one" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			armed = []
			canceled = []
			ticket = 0
			add = ->(_t, &_b) { ticket += 1; armed << ticket; ticket }

			with_em(add_timer: add, cancel_timer: ->(timer) { canceled << timer }) do
				connection.send(:arm_timeout, "evt1") { nil } # first window: timer #1, nothing to cancel yet
				connection.send(:arm_timeout, "evt1") { nil } # re-arm: cancel #1, then arm #2
			end

			assert_equal [ 1, 2 ], armed, "each arm adds a fresh EM timer"
			assert_equal [ 1 ], canceled, "the prior timer is cancelled exactly once before the re-arm (no leak)"
			assert_equal 2, connection.send(:timers)["evt1"], "only the freshest timer id is retained"
		end

		# --- thread-safety ---

		test "concurrent connect opens exactly one socket (guarded check-then-transition)" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			count = 0
			count_mutex = Mutex.new
			reactor = NostrClient::Reactor.instance
			reactor.define_singleton_method(:schedule) { |&_b| count_mutex.synchronize { count += 1 } }

			8.times.map { Thread.new { connection.connect } }.each(&:join)

			assert_equal 1, count, "only the first racing connect transitions and schedules open_socket"
		ensure
			reactor.singleton_class.send(:remove_method, :schedule)
		end

		test "resubscribe iterates a snapshot so a concurrent subscribe cannot corrupt the loop" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			connection.send(:transition_to, :connected)
			connection.subscriptions["a"] = [ { kinds: [ 1 ] } ]
			connection.subscriptions["b"] = [ { kinds: [ 2 ] } ]
			connection.define_singleton_method(:send_frame) do |*_frame|
				subscriptions["added-#{subscriptions.size}"] = [ { kinds: [ 9 ] } ] # mutate mid-iteration
			end

			assert_nothing_raised { connection.send(:resubscribe) }
		end
	end
end
