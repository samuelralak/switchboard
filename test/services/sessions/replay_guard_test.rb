# frozen_string_literal: true

require "test_helper"

module Sessions
	class ReplayGuardTest < ActiveSupport::TestCase
		# A real store: the test-env Rails.cache is the null store, which accepts every write.
		setup { @store = ActiveSupport::Cache::MemoryStore.new }

		test "admits the first use of an event id" do
			assert_nothing_raised { reserve(SecureRandom.hex(32)) }
		end

		test "rejects a second use of the same event id" do
			id = SecureRandom.hex(32)
			reserve(id)

			assert_raises(AuthenticationError) { reserve(id) }
		end

		test "admits distinct event ids" do
			reserve(SecureRandom.hex(32))

			assert_nothing_raised { reserve(SecureRandom.hex(32)) }
		end

		test "still blocks the id within the TTL window" do
			id = SecureRandom.hex(32)
			reserve(id)

			travel(ReplayGuard::TTL.seconds - 1) do
				assert_raises(AuthenticationError) { reserve(id) }
			end
		end

		test "admits the same id again once the entry has expired" do
			id = SecureRandom.hex(32)
			reserve(id)

			travel(ReplayGuard::TTL.seconds + 1) do
				assert_nothing_raised { reserve(id) }
			end
		end

		private

		def reserve(event_id) = ReplayGuard.call(event_id:, store: @store)
	end
end
