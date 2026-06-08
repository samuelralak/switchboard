# frozen_string_literal: true

require "test_helper"

module Orders
	class MarkReleasedTest < ActiveSupport::TestCase
		test "records the observable release assertion on a funded order, leaving current_state funded" do
			order = funded
			at = Time.current.to_i

			release = Orders::MarkReleased.call(order:, reveal_event_id: hex, released_at: at)

			assert release.persisted?
			assert_equal Orders::States::FUNDED, order.reload.current_state, "release does NOT advance the state machine"
			assert_equal at, order.release.released_at.to_i
		end

		test "is idempotent per order: a re-reveal supersedes the prior assertion" do
			order = funded
			Orders::MarkReleased.call(order:, reveal_event_id: hex, released_at: Time.current.to_i)
			second = hex
			Orders::MarkReleased.call(order:, reveal_event_id: second, released_at: Time.current.to_i)

			assert_equal 1, OrderRelease.where(order:).count
			assert_equal second, order.reload.release.reveal_event_id
		end

		test "rejects release on an unfunded order" do
			order = build_order # awaiting_funding

			assert_raises(IllegalTransitionError) do
				Orders::MarkReleased.call(order:, reveal_event_id: hex, released_at: Time.current.to_i)
			end
		end

		test "rejects a non-hex reveal event id" do
			order = funded

			assert_raises(ActiveRecord::RecordInvalid) do
				Orders::MarkReleased.call(order:, reveal_event_id: "nope", released_at: Time.current.to_i)
			end
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
