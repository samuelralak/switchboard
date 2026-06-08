# frozen_string_literal: true

require "test_helper"

module Escrow
	class ExpireSweepJobTest < ActiveJob::TestCase
		test "expires unfunded orders past the funding deadline" do
			due = build_order(funding_deadline_at: 1.minute.ago)
			fresh = build_order(funding_deadline_at: 1.hour.from_now)

			Escrow::ExpireSweepJob.perform_now

			assert_equal Orders::States::EXPIRED, due.reload.current_state
			assert_equal Orders::States::AWAITING_FUNDING, fresh.reload.current_state
		end

		test "never expires a funded order, even past its deadline" do
			order = build_order(funding_deadline_at: 1.minute.ago)
			fund_order(order)

			Escrow::ExpireSweepJob.perform_now

			assert_equal Orders::States::FUNDED, order.reload.current_state
		end
	end
end
