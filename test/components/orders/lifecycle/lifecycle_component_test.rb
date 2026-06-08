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
		end
	end
end
