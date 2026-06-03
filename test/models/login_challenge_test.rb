# frozen_string_literal: true

require "test_helper"

class LoginChallengeTest < ActiveSupport::TestCase
	test "issue creates a fresh, unconsumed, future-dated challenge" do
		challenge = LoginChallenge.issue

		assert_match(/\A[a-f0-9]{64}\z/, challenge.nonce)
		assert_nil challenge.consumed_at
		assert challenge.expires_at > Time.current
	end

	test "consume returns the nonce once, then nil (single use)" do
		nonce = LoginChallenge.issue.nonce

		assert_equal nonce, LoginChallenge.consume(nonce)
		assert_nil LoginChallenge.consume(nonce)
	end

	test "consume returns nil for an unknown nonce" do
		assert_nil LoginChallenge.consume(SecureRandom.hex(32))
	end

	test "consume returns nil for an expired challenge" do
		challenge = LoginChallenge.create!(nonce: SecureRandom.hex(32), expires_at: 1.second.ago)

		assert_nil LoginChallenge.consume(challenge.nonce)
	end

	# Real threads + commits to exercise the single-statement UPDATE gate.
	class ConcurrencyTest < ActiveSupport::TestCase
		self.use_transactional_tests = false

		teardown { LoginChallenge.delete_all }

		test "exactly one of two concurrent consumers claims the nonce" do
			20.times do
				nonce = LoginChallenge.issue.nonce # fresh per iteration, so iterations cannot collide

				winners = [ 1, 2 ].map do
					Thread.new { ActiveRecord::Base.connection_pool.with_connection { LoginChallenge.consume(nonce) } }
				end.map(&:value)

				assert_equal [ nonce ], winners.compact
			end
		end
	end
end
