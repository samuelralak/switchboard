# frozen_string_literal: true

require "test_helper"

module Orders
	class ExpireIfDueTest < ActiveSupport::TestCase
		test "expires an unfunded order past its funding deadline" do
			order = build_order(funding_deadline_at: 1.minute.ago)

			Orders::ExpireIfDue.call(order:)

			assert_equal Orders::States::EXPIRED, order.reload.current_state
		end

		test "leaves an unfunded order whose deadline has not passed" do
			order = build_order(funding_deadline_at: 1.hour.from_now)

			Orders::ExpireIfDue.call(order:)

			assert_equal Orders::States::AWAITING_FUNDING, order.reload.current_state
		end

		test "never expires a funded order, even past its deadline" do
			order, = fund_order(build_order(funding_deadline_at: 1.minute.ago))

			Orders::ExpireIfDue.call(order:)

			assert_equal Orders::States::FUNDED, order.reload.current_state
		end
	end
end
