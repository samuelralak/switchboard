# frozen_string_literal: true

require "test_helper"

module Messages
	module Actions
		class RandomPastTimestampTest < ActiveSupport::TestCase
			test "is always within the last two days and never in the future" do
				now = 1_700_000_000
				200.times do
					t = Messages::Actions::RandomPastTimestamp.call(now: now)
					assert_operator t, :<=, now
					assert_operator t, :>=, now - Messages::Actions::RandomPastTimestamp::TWO_DAYS
				end
			end
		end
	end
end
