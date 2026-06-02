# frozen_string_literal: true

module Shared
  module Lamp
    class LampComponentPreview < ViewComponent::Preview
      def current
        render(LampComponent.new(status: :current))
      end

      def done
        render(LampComponent.new(status: :done))
      end

      def settled
        render(LampComponent.new(status: :settled))
      end

      def fault
        render(LampComponent.new(status: :fault))
      end

      def future
        render(LampComponent.new(status: :future))
      end
    end
  end
end
