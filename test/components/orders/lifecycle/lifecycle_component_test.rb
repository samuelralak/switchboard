# frozen_string_literal: true

require "test_helper"

module Orders
	module Lifecycle
		class LifecycleComponentTest < ViewComponent::TestCase
			test "renders the stepper with the node labels and the escrow rail" do
				order = build_order
				order.state_machine.transition_to!(Orders::States::FUNDED)

				render_inline(LifecycleComponent.new(order:))

				assert_text "Awaiting funding"
				assert_text "Funded, in escrow"
				assert_text "escrow"
			end

			test "the released order shows the released node" do
				order = build_order
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order.state_machine.transition_to!(Orders::States::RELEASED)

				render_inline(LifecycleComponent.new(order:))

				assert_text "Released to provider"
			end

			test "a delivered + released funded order reads as releasing, awaiting redemption" do
				order = build_order
				order.state_machine.transition_to!(Orders::States::FUNDED)
				Orders::MarkDelivered.call(order:, delivery_event_id: SecureRandom.hex(32),
					delivered_at: Time.current.to_i, content_hash: SecureRandom.hex(32))
				Orders::MarkReleased.call(order:, reveal_event_id: SecureRandom.hex(32), released_at: Time.current.to_i)

				component = LifecycleComponent.new(order:)
				render_inline(component)

				assert_equal "releasing", component.chip_label, "the headline chip reflects the release"
				assert_text "Released, awaiting redemption"
			end
		end
	end
end
