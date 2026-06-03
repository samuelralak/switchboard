# frozen_string_literal: true

module Shared
	module Stepper
		class StepperComponentPreview < ViewComponent::Preview
			def default
				render(StepperComponent.new(steps: %w[Compose Confirm Track Receive], active: 2))
			end

			def first_step
				render(StepperComponent.new(steps: %w[Compose Confirm Track Receive], active: 1))
			end

			def last_step
				render(StepperComponent.new(steps: %w[Compose Confirm Track Receive], active: 4))
			end
		end
	end
end
