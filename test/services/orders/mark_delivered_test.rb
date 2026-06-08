# frozen_string_literal: true

require "test_helper"

module Orders
	class MarkDeliveredTest < ActiveSupport::TestCase
		test "records the observable delivery assertion on a funded order, leaving current_state funded" do
			order = funded
			at = Time.current.to_i

			delivery = Orders::MarkDelivered.call(order:, delivery_event_id: hex, delivered_at: at, content_hash: hex)

			assert delivery.persisted?
			assert_equal Orders::States::FUNDED, order.reload.current_state, "delivery does NOT advance the state machine"
			assert_equal at, order.delivery.delivered_at.to_i
		end

		test "is idempotent per order: a re-delivery supersedes the prior assertion" do
			order = funded
			first = hex
			Orders::MarkDelivered.call(order:, delivery_event_id: first, delivered_at: Time.current.to_i, content_hash: hex)
			second = hex
			Orders::MarkDelivered.call(order:, delivery_event_id: second, delivered_at: Time.current.to_i, content_hash: hex)

			assert_equal 1, OrderDelivery.where(order:).count
			assert_equal second, order.reload.delivery.delivery_event_id
		end

		test "rejects delivery on an unfunded order" do
			order = build_order # awaiting_funding

			assert_raises(IllegalTransitionError) do
				Orders::MarkDelivered.call(order:, delivery_event_id: hex, delivered_at: Time.current.to_i, content_hash: hex)
			end
		end

		test "rejects a non-hex event id" do
			order = funded
			args = { order:, delivery_event_id: "nope", delivered_at: Time.current.to_i, content_hash: hex }

			assert_raises(ActiveRecord::RecordInvalid) { Orders::MarkDelivered.call(**args) }
		end

		private

		def funded
			order = build_order
			order.state_machine.transition_to!(Orders::States::FUNDED)
			order
		end

		def hex = SecureRandom.hex(32)
	end
end
