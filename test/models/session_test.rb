# frozen_string_literal: true

require "test_helper"

class SessionTest < ActiveSupport::TestCase
	test "is destroyed when its user is destroyed" do
		user = User.create!(pubkey: SecureRandom.hex(32))
		user.sessions.create!

		assert_difference -> { Session.count }, -1 do
			user.destroy
		end
	end
end
