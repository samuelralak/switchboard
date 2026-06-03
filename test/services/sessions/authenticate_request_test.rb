# frozen_string_literal: true

require "test_helper"

module Sessions
	class AuthenticateRequestTest < ActiveSupport::TestCase
		URL = "https://switchboard.test/api/identity"

		setup { @store = ActiveSupport::Cache::MemoryStore.new }

		test "returns the user for a valid stateless request" do
			event = sign_nip98(tags: nip98_tags(url: URL, http_method: "GET"))

			user = authenticate(event)

			assert_instance_of User, user
			assert_equal event["pubkey"], user.pubkey
		end

		test "rejects a replay of the same signed request" do
			event = sign_nip98(tags: nip98_tags(url: URL, http_method: "GET"))
			authenticate(event)

			assert_raises(AuthenticationError) { authenticate(event) }
		end

		test "creates no session row" do
			event = sign_nip98(tags: nip98_tags(url: URL, http_method: "GET"))

			assert_no_difference -> { Session.count } do
				authenticate(event)
			end
		end

		test "delegates NIP-98 gate failures to the shared verifier" do
			event = sign_nip98(tags: nip98_tags(url: URL, http_method: "GET"))
			event["content"] = "tampered"

			assert_raises(InvalidEventError) { authenticate(event) }
		end

		private

		def authenticate(event)
			AuthenticateRequest.call(event_data: event, http_method: "GET", url: URL, store: @store)
		end
	end
end
