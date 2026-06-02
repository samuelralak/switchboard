# frozen_string_literal: true

module Shared
  module Stepper
    # A compact, horizontal progress stepper matching the prototype. Renders a row
    # of numbered steps with connectors between them. Each step is in one of three
    # states relative to the 1-based +active+ index:
    #   done    (i < active)  filled copper circle with a check mark
    #   current (i == active) outlined copper circle showing the step number
    #   future  (i > active)  faint outlined circle showing the step number
    # Pass the step labels as +steps+ and the active step (1-based) as +active+.
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
