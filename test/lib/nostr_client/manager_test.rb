# frozen_string_literal: true

require "test_helper"

module NostrClient
	class ManagerTest < ActiveSupport::TestCase
		test "handle_ok delegates the OK verdict to the originating connection" do
			captured = nil
			connection = Object.new
			connection.define_singleton_method(:settle_ok) { |id, accepted, text| captured = [ id, accepted, text ] }

			NostrClient::Manager.instance.send(:handle_ok, connection, "evt1", true, "ok")

			assert_equal [ "evt1", true, "ok" ], captured
		end

		test "handle_auth only stores the relay challenge (lazy: it does not authenticate)" do
			captured = nil
			authed = false
			connection = Object.new
			connection.define_singleton_method(:store_challenge) { |challenge| captured = challenge }
			connection.define_singleton_method(:authenticate) { authed = true }

			NostrClient::Manager.instance.send(:handle_auth, connection, "chal-xyz")

			assert_equal "chal-xyz", captured
			assert_not authed, "lazy AUTH: the unsolicited challenge must not trigger signing"
		end

		test "handle_closed authenticates on an auth-required close instead of dropping" do
			authed = false
			connection = Object.new
			connection.define_singleton_method(:auth_required?) { |reason| reason.to_s.start_with?("auth-required:") }
			connection.define_singleton_method(:authenticate) { authed = true }

			NostrClient::Manager.instance.send(:handle_closed, connection, "sub1", "auth-required: x")

			assert authed
		end

		test "handle_closed drops the subscription on a normal (non-auth) CLOSED" do
			dropped = nil
			connection = Object.new
			connection.define_singleton_method(:auth_required?) { |reason| reason.to_s.start_with?("auth-required:") }
			connection.define_singleton_method(:url) { "wss://relay.test" }
			connection.define_singleton_method(:drop_subscription) { |sub_id| dropped = sub_id }

			NostrClient::Manager.instance.send(:handle_closed, connection, "sub1", "duplicate: already have it")

			assert_equal "sub1", dropped
		end

		test "malformed? rejects a known frame whose payload arity is out of range (too few OR too many)" do
			manager = NostrClient::Manager.instance
			ok = NostrClient::Messages::Inbound::OK

			assert manager.send(:malformed?, ok, [ "evt1" ]) # too few (min 2)
			assert manager.send(:malformed?, ok, [ "e", true, "m", "x" ]) # too many (max 3)
			assert_not manager.send(:malformed?, ok, [ "evt1", true ]) # exactly 2
			assert_not manager.send(:malformed?, ok, [ "evt1", true, "msg" ]) # exactly 3
			assert_not manager.send(:malformed?, "WHATEVER", []) # unknown type: not validated, falls through
		end
	end
end
