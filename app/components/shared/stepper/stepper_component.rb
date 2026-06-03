# frozen_string_literal: true

module Shared
	module Stepper
		# Renders a horizontal progress stepper for +steps+ with the 1-based +active+ step highlighted.
		class StepperComponent < ApplicationComponent
			CIRCLE = {
				done: "bg-copper text-canvas",
				current: "border border-copper text-copper",
				future: "border border-border-strong text-ink-faint"
			}.freeze

			LABEL = {
				done: "text-ink-muted",
				current: "text-ink",
				future: "text-ink-muted"
			}.freeze

			CONNECTOR = { done: "bg-copper-dim", other: "bg-border-strong" }.freeze

			attr_reader :steps

			def initialize(steps: [], active: 1)
				@steps = Array(steps)
				@active = active.to_i
			end

			def state_for(index)
				return :done if index < @active

				index == @active ? :current : :future
			end

			def circle_class(index) = CIRCLE.fetch(state_for(index))
			def label_class(index) = LABEL.fetch(state_for(index))
			def mark_for(index) = index < @active ? "✓" : index
			def connector_class(index) = index < @active ? CONNECTOR[:done] : CONNECTOR[:other]
			def last_step?(index) = index == @steps.length
		end
	end
end
