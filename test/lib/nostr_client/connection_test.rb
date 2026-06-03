# frozen_string_literal: true

require "test_helper"

module NostrClient
	class ConnectionTest < ActiveSupport::TestCase
		test "does not reconnect after a deliberate stop" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) {})

			connection.disconnect # marks stopping and returns early (it never connected)
			connection.send(:schedule_reconnect)

			assert_equal 0, connection.reconnect_attempts
		end

		test "schedules a reconnect after an unexpected drop" do
			connection = NostrClient::Connection.new(url: "wss://relay.test", on_message: ->(*) {})
			connection.send(:transition_to, :connected)
			scheduled = false
			connection.define_singleton_method(:schedule_reconnect) { scheduled = true }

			connection.send(:on_close, Struct.new(:code).new(1006))

			assert scheduled
		end
	end
end
