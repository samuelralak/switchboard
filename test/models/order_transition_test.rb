# frozen_string_literal: true

require "test_helper"

class OrderTransitionTest < ActiveSupport::TestCase
	test "to_state is constrained to a known state" do
		order = build_order

		assert_raises(ActiveRecord::StatementInvalid) do
			order.order_transitions.create!(from_state: "funded", to_state: "bogus", sort_key: 10, most_recent: true)
		end
	end

	test "only one most_recent transition per order" do
		order = build_order
		order.order_transitions.create!(from_state: "awaiting_funding", to_state: "funded", sort_key: 10, most_recent: true)

		assert_raises(ActiveRecord::RecordNotUnique) do
			order.order_transitions.create!(from_state: "funded", to_state: "released", sort_key: 20, most_recent: true)
		end
	end

	test "sort_key is unique per order" do
		order = build_order
		order.order_transitions.create!(from_state: "awaiting_funding", to_state: "funded", sort_key: 10)

		assert_raises(ActiveRecord::RecordNotUnique) do
			order.order_transitions.create!(from_state: "funded", to_state: "released", sort_key: 10)
		end
	end
end
