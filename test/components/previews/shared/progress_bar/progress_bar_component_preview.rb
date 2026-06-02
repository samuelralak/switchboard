# frozen_string_literal: true

module Shared
  module ProgressBar
    class ProgressBarComponentPreview < ViewComponent::Preview
      def fraction_with_value
        render(ProgressBarComponent.new(value: 0.94, show_value: true))
      end

      def fraction_bare
        render(ProgressBarComponent.new(value: 0.5))
      end

      def percentage_integer
        render(ProgressBarComponent.new(value: 72, show_value: true))
      end

      def empty
        render(ProgressBarComponent.new(value: 0, show_value: true))
      end

      def full
        render(ProgressBarComponent.new(value: 1.0, show_value: true))
      end
    end
  end
end
