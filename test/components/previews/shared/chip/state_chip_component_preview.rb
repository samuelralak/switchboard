# frozen_string_literal: true

module Shared
	module Chip
		class StateChipComponentPreview < ViewComponent::Preview
			def completed
				render(StateChipComponent.new(state: :completed))
			end

			def open
				render(StateChipComponent.new(state: :open))
			end

			def claimed
				render(StateChipComponent.new(state: :claimed))
			end

			def failed
				render(StateChipComponent.new(state: :failed))
			end

			def cancelled
				render(StateChipComponent.new(state: :cancelled))
			end

			def string_state
				render(StateChipComponent.new(state: "verifying_delivery"))
			end

			def unknown_state
				render(StateChipComponent.new(state: :archived))
			end
		end
	end
end
