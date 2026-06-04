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
			[ conn, socket_sent ]
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

			(NostrClient::Authentication::MAX_AUTH_ATTEMPTS + 2).times { conn.authenticate }

			assert_equal NostrClient::Authentication::MAX_AUTH_ATTEMPTS, auth_frames(sent).size
		ensure
			NostrClient.configure { |c| c.auth_signer = nil }
		end

		test "a successful AUTH resets the cap so a rotated challenge can re-authenticate" do
			NostrClient.configure { |c| c.auth_signer = fake_signer }
			conn, sent = stubbed_connection
			conn.store_challenge("chal")

			NostrClient::Authentication::MAX_AUTH_ATTEMPTS.times { conn.authenticate }
			assert_not conn.authenticate, "cap is reached"
			conn.on_authenticated # the relay accepted one of them
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
