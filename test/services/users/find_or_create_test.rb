# frozen_string_literal: true

require "test_helper"

module Users
	class FindOrCreateTest < ActiveSupport::TestCase
		test "creates a bare row with first_seen_at and no profile" do
			pubkey = SecureRandom.hex(32)

			user = Users::FindOrCreate.call(pubkey:)

			assert user.persisted?
			assert_equal pubkey, user.pubkey
			assert_not_nil user.first_seen_at
			assert_nil user.name
			assert_nil user.metadata_event_id
		end

		test "returns the existing row on a repeat call" do
			pubkey = SecureRandom.hex(32)
			first = Users::FindOrCreate.call(pubkey:)
			second = Users::FindOrCreate.call(pubkey:)

			assert_equal first.id, second.id
			assert_equal 1, User.where(pubkey:).count
		end

		test "raises on an invalid pubkey" do
			assert_raises(ActiveRecord::RecordInvalid) { Users::FindOrCreate.call(pubkey: "not-hex") }
		end
	end
end
