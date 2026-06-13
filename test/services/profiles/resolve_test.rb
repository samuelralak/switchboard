# frozen_string_literal: true

require "test_helper"

module Profiles
	class ResolveTest < ActiveSupport::TestCase
		test "raises RecordNotFound for an operator-flagged identity (takedown)" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, name: "scammer", flagged: true)

			assert_raises(ActiveRecord::RecordNotFound) do
				Profiles::Resolve.call(npub: user.npub, viewer: nil)
			end
		end

		test "resolves a normal, unflagged identity" do
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, name: "alice")

			assert_not_nil Profiles::Resolve.call(npub: user.npub, viewer: nil)
		end
	end
end
