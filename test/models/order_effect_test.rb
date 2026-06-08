# frozen_string_literal: true

require "test_helper"

class OrderEffectTest < ActiveSupport::TestCase
	test "at most one effect per order" do
		order = build_order
		order.effects.create!(kind: Orders::States::RELEASED)

		assert_raises(ActiveRecord::RecordNotUnique) { order.effects.create!(kind: Orders::States::REFUNDED) }
	end

	test "kind check constraint at the database" do
		order = build_order
		effect = OrderEffect.new(order:, kind: "funded")

		assert_raises(ActiveRecord::StatementInvalid) { effect.save(validate: false) }
	end

	test "rejects a non-settlement kind at the model" do
		order = build_order

		assert_not order.effects.build(kind: "funded").valid?
	end
end
