# frozen_string_literal: true

module Shared
  module Button
    class ButtonComponentPreview < ViewComponent::Preview
      def primary
        render(ButtonComponent.new(variant: :primary, icon: "rocket-01").with_content("Publish"))
      end

      def ghost
        render(ButtonComponent.new(variant: :ghost, trailing_icon: "arrow-right-01").with_content("Learn more"))
      end

      def sizes
        render(ButtonComponent.new(size: :lg).with_content("Large action"))
      end

      def full_width
        render(ButtonComponent.new(variant: :primary, full: true).with_content("Continue"))
      end

      def link
        render(ButtonComponent.new(tag: :a, href: "#", variant: :ghost).with_content("View listing"))
      end

      def disabled
        render(ButtonComponent.new(disabled: true).with_content("Submitting"))
      end
    end
  end
end
