# frozen_string_literal: true

require "test_helper"

module NostrClient
	# Shared stubs for the NIP-42 AUTH test classes.
	module AuthenticationTestSupport
		AUTH = NostrClient::Messages::Outbound::AUTH

		# A stand-in R_op signer: returns a deterministic signed-shaped event (id "authid").
		def fake_signer
			signer = Object.new
			signer.define_singleton_method(:sign) do |kind:, tags:, content:|
				{ "id" => "authid", "pubkey" => "rop", "kind" => kind, "tags" => tags, "content" => content, "sig" => "s" }
			end
			signer
		end

		# A connected connection whose frame sends are captured (as arrays) and resubscribe neutralized.
		def stubbed_connection
			conn = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			conn.send(:transition_to, :connected)
			sent = []
			conn.define_singleton_method(:send_frame) { |*frame| sent << frame }
			conn.define_singleton_method(:resubscribe) { nil }
			[ conn, sent ]
		end

		# A connected connection with a fake socket that captures raw EVENT re-sends as JSON.
		def connection_with_socket
			conn = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) { })
			conn.send(:transition_to, :connected)
			socket_sent = []
			socket = Object.new
			socket.define_singleton_method(:send) { |json| socket_sent << json }
			conn.instance_variable_set(:@socket, socket)
			conn.define_singleton_method(:send_frame) { |*| nil }
			conn.define_singleton_method(:resubscribe) { nil }
			stub_timer_seam(conn)
			[ conn, socket_sent ]
		end

		# Timer seam without a live reactor: record armed timeouts (and their blocks) into the real timers
		# table so re-arming on defer/resend is observable, and settle's cancel is a plain delete.
		def stub_timer_seam(conn)
			conn.define_singleton_method(:arm_timeout) { |id, &blk| send(:timers)[id] = (blk || true) }
			conn.define_singleton_method(:cancel_timeout) { |id| send(:timers).delete(id) }
		end

		def auth_frames(sent) = sent.select { |frame| frame.first == AUTH }
	end

	class AuthenticationTest < ActiveSupport::TestCase
		include AuthenticationTestSupport

		test "authenticate signs a kind-22242 over relay + challenge and sends AUTH" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal-123")

			assert conn.authenticate

			event = auth_frames(sent).first&.last
			assert event, "expected an AUTH frame to be sent"
			assert_equal NostrClient::Authentication::AUTH_KIND, event["kind"]
			assert_includes event["tags"], [ "relay", "wss://relay.test" ]
			assert_includes event["tags"], %w[challenge chal-123]
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "storing a challenge does not send AUTH (lazy: R_op authenticates only when gated)" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection

			conn.store_challenge("chal-123")

			assert_empty auth_frames(sent)
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "sends no AUTH when no signer is configured" do
			NostrClient.configure { |c| c.auth_signer = nil }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")

			assert_not conn.authenticate
			assert_empty auth_frames(sent)
		end

		test "challenge rotation cannot drive unbounded signing: a rotate+reject loop stays capped" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection

			# A hostile relay that rotates its challenge and rejects each AUTH must not extract more than the
			# per-connection cap; the cap resets only on a genuine AUTH OK or on disconnect, never on rotation.
			10.times do |i|
				conn.store_challenge("chal-#{i}")
				conn.authenticate
				conn.on_auth_failed # the relay rejects: clears the in-flight id but NOT the attempt cap
			end

			assert_equal NostrClient::Authentication::MAX_AUTH_ATTEMPTS, auth_frames(sent).size
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "an in-flight AUTH blocks a second authenticate until it resolves" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")

			assert conn.authenticate, "the first AUTH goes out"
			assert_not conn.authenticate, "a second is blocked while one is in flight (no parallel signing)"

			assert_equal 1, auth_frames(sent).size
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "on_close clears an in-flight AUTH so the relay can re-authenticate after reconnect" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = stubbed_connection
			conn.define_singleton_method(:schedule_reconnect) { nil }
			conn.store_challenge("chal")
			assert conn.authenticate
			assert conn.auth_in_flight?

			conn.send(:on_close, Struct.new(:code).new(1006)) # drop mid-AUTH

			assert_not conn.auth_in_flight?, "on_close must clear the in-flight AUTH id"
			conn.send(:transition_to, :connected)
			conn.store_challenge("chal2") # relay re-challenges after reconnect
			assert conn.authenticate, "a fresh challenge re-authenticates after the drop"
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "does not sign AUTH for an empty or non-string challenge" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection

			conn.store_challenge("")
			assert_not conn.authenticate
			conn.store_challenge({ "not" => "a string" })
			assert_not conn.authenticate

			assert_empty auth_frames(sent)
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end
	end

	# The NIP-42 auth-required EVENT flow: defer, authenticate, re-send, and the attempt cap.
	class AuthRequiredFlowTest < ActiveSupport::TestCase
		include AuthenticationTestSupport

		test "an auth-required EVENT defers, authenticates, and re-sends the event after the AUTH OK" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, socket_sent = connection_with_socket
			conn.store_challenge("chal")
			queue = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue:, event: { "id" => "evt1", "kind" => 1 } }

			conn.settle_ok("evt1", false, "auth-required: please authenticate")
			assert queue.empty?, "the publish must not settle until AUTH resolves"

			conn.settle_ok("authid", true, "") # the relay accepts our AUTH credential
			resent = socket_sent.map { |j| JSON.parse(j) }.select { |f| f.first == "EVENT" && f.last["id"] == "evt1" }
			assert_equal 1, resent.size, "the deferred event is re-sent exactly once after AUTH"

			conn.settle_ok("evt1", true, "") # the relay now accepts the re-sent event
			assert_equal :ok, queue.pop.status
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a restricted OK settles as :rejected without authenticating" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")
			queue = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue:, event: { "id" => "evt1" } }

			conn.settle_ok("evt1", false, "restricted: key not allowed")

			assert_equal :rejected, queue.pop.status
			assert_empty auth_frames(sent)
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "caps repeated failed authentication attempts to avoid loops" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")

			# Each round: AUTH out, relay rejects (on_auth_failed clears the in-flight id). The cap stops it.
			(NostrClient::Authentication::MAX_AUTH_ATTEMPTS + 2).times do
				conn.authenticate
				conn.on_auth_failed
			end

			assert_equal NostrClient::Authentication::MAX_AUTH_ATTEMPTS, auth_frames(sent).size
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a successful AUTH resets the cap so a later challenge can re-authenticate" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")

			NostrClient::Authentication::MAX_AUTH_ATTEMPTS.times do
				conn.authenticate
				conn.on_auth_failed # relay rejects; clears the in-flight id, not the cap
			end
			assert_not conn.authenticate, "cap is reached"

			conn.on_authenticated # the relay finally accepts one
			assert conn.authenticate, "cap reset after a successful AUTH"

			assert_equal NostrClient::Authentication::MAX_AUTH_ATTEMPTS + 1, auth_frames(sent).size
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "never logs the AUTH credential" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = stubbed_connection
			conn.store_challenge("chal")
			io = StringIO.new
			original = Rails.logger
			Rails.logger = ActiveSupport::Logger.new(io)

			conn.authenticate
			conn.settle_ok("authid", true, "")

			assert_not_includes io.string, "authid"
			assert_not_includes io.string, "\"sig\""
		ensure
			Rails.logger = original
			NostrClient.configure { |c| c.auth_signer = nil }
		end
	end

	# Resolving an in-flight AUTH credential: re-send every deferred event on accept, settle on reject.
	class AuthResolutionTest < ActiveSupport::TestCase
		include AuthenticationTestSupport

		test "re-sends every deferred event (not just one) after a single AUTH OK" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, socket_sent = connection_with_socket
			conn.store_challenge("chal")
			q1 = Thread::Queue.new
			q2 = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue: q1, event: { "id" => "evt1" } }
			conn.send(:pending)["evt2"] = { queue: q2, event: { "id" => "evt2" } }

			conn.settle_ok("evt1", false, "auth-required: x")
			conn.settle_ok("evt2", false, "auth-required: x")
			conn.settle_ok("authid", true, "") # one AUTH OK must re-send BOTH deferred events

			resent = socket_sent.map { |j| JSON.parse(j) }.select { |f| f.first == "EVENT" }.map { |f| f.last["id"] }
			assert_equal %w[evt1 evt2], resent.sort
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a deferred publish re-arms a fresh timeout on defer and again on re-send" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = connection_with_socket
			conn.store_challenge("chal")
			queue = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue:, event: { "id" => "evt1" } }

			conn.settle_ok("evt1", false, "auth-required: x") # defer + authenticate: an AUTH-wait timeout is armed
			assert conn.send(:timers).key?("evt1"), "a timeout is armed while AUTH is in flight"
			assert queue.empty?, "the publish does not settle until AUTH resolves"

			conn.settle_ok("authid", true, "") # AUTH OK: resend_deferred re-arms a fresh publish timeout
			assert conn.send(:timers).key?("evt1"), "the re-sent publish gets a fresh window, not the elapsed one"
			assert queue.empty?, "the re-sent publish waits for its own OK"
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a stalled AUTH (accepted frame, no OK) is released so the next gated op can re-authenticate" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = connection_with_socket
			conn.store_challenge("chal")
			q1 = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue: q1, event: { "id" => "evt1" } }

			conn.settle_ok("evt1", false, "auth-required: x") # defers + authenticates (authid in flight)
			assert conn.auth_in_flight?, "an AUTH is in flight"

			conn.send(:timers).fetch("evt1").call # the relay never OKs: the AUTH-wait timeout fires
			assert_equal :auth_required, q1.pop.status, "the stalled caller unblocks"
			assert_not conn.auth_in_flight?, "the stalled AUTH is released, not orphaned"

			q2 = Thread::Queue.new
			conn.send(:pending)["evt2"] = { queue: q2, event: { "id" => "evt2" } }
			conn.settle_ok("evt2", false, "auth-required: y")

			assert conn.auth_in_flight?, "a later gated op sends a fresh AUTH instead of waiting on the dead one"
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "an AUTH-wait timeout keeps the in-flight AUTH while a sibling publish still awaits it" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, socket_sent = connection_with_socket
			conn.store_challenge("chal")
			q1 = Thread::Queue.new
			q2 = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue: q1, event: { "id" => "evt1" } }
			conn.send(:pending)["evt2"] = { queue: q2, event: { "id" => "evt2" } }

			conn.settle_ok("evt1", false, "auth-required: x") # authenticates (authid in flight)
			conn.settle_ok("evt2", false, "auth-required: x") # waits on the SAME in-flight AUTH

			conn.send(:timers).fetch("evt1").call # evt1's AUTH-wait fires, but evt2 still awaits
			assert_equal :auth_required, q1.pop.status
			assert conn.auth_in_flight?, "the AUTH is kept while a sibling still rides it"

			conn.settle_ok("authid", true, "") # a late real AUTH OK re-sends only the still-awaiting evt2
			resent = socket_sent.map { |json| JSON.parse(json) }.select { |f| f.first == "EVENT" }.map { |f| f.last["id"] }
			assert_equal [ "evt2" ], resent
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a black-holing relay (rotate + stall) cannot extract more than the cap of R_op signings" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = connection_with_socket
			auth_sent = []
			conn.define_singleton_method(:send_frame) { |*frame| auth_sent << frame }

			(NostrClient::Authentication::MAX_AUTH_ATTEMPTS + 3).times do |i|
				id = "evt#{i}"
				conn.store_challenge("chal-#{i}") # the relay rotates its challenge each round
				conn.send(:pending)[id] = { queue: Thread::Queue.new, event: { "id" => id } }
				conn.settle_ok(id, false, "auth-required: x") # defer + authenticate (or settle-now once capped)
				conn.send(:timers)[id]&.call # the relay never OKs: fire the AUTH-wait timer (stall path) if armed
			end

			# settle_auth_wait must NOT reset @auth_attempts, so the stall path still trips the cap and stops signing.
			signings = auth_sent.count { |frame| frame.first == AUTH }
			assert_equal NostrClient::Authentication::MAX_AUTH_ATTEMPTS, signings
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "an auth-required EVENT with no usable signer settles :auth_required now, not only on the timeout" do
			NostrClient.configure { |c| c.auth_signer = nil }
			conn, = connection_with_socket
			queue = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue:, event: { "id" => "evt1" } }

			conn.settle_ok("evt1", false, "auth-required: x")

			assert_not conn.auth_in_flight?, "no AUTH was sent (no signer)"
			assert_equal :auth_required, queue.pop.status, "the caller settles immediately, not only on the timer"
			assert_not conn.send(:pending).key?("evt1"), "the pending entry is cleared"
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "an AUTH rejection settles the deferred publish and clears the in-flight auth for retry" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, = connection_with_socket
			conn.store_challenge("chal")
			queue = Thread::Queue.new
			conn.send(:pending)["evt1"] = { queue:, event: { "id" => "evt1" } }

			conn.settle_ok("evt1", false, "auth-required: please") # defer + authenticate (auth id "authid")
			assert queue.empty?, "the publish must not settle while AUTH is in flight"
			assert conn.awaiting_auth_ok?("authid")

			conn.settle_ok("authid", false, "error: bad credential") # the relay REJECTS our AUTH

			assert_equal :auth_required, queue.pop.status, "the deferred caller is unblocked, not left hanging"
			assert_not conn.awaiting_auth_ok?("authid"), "the in-flight auth is cleared so a later gated op can retry"
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end
	end
end
