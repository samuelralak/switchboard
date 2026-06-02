# frozen_string_literal: true

module Shared
  module Card
    class CardComponentPreview < ViewComponent::Preview
      # @param padding select { choices: [none, p4, p5, p6, p7] }
      # @param interactive toggle
      # @param accent select { choices: [none, copper] }
      def playground(padding: :p6, interactive: false, accent: :none)
        component = CardComponent.new(
          padding: padding.to_sym,
          interactive: interactive,
          accent: accent.to_sym == :none ? nil : accent.to_sym
        )
        render(component.with_content("Funds lock at request and release only on delivery."))
      end

      def default
        render(CardComponent.new.with_content("A surface panel on bg-surface."))
      end

      def padded_p5
        render(CardComponent.new(padding: :p5).with_content("Compact p-5 status panel."))
      end

      def interactive
        render(CardComponent.new(interactive: true).with_content("Hover and focus me; I am a button."))
      end

      def copper_accent_link
        component = CardComponent.new(accent: :copper, tag: :a, href: "#")
        render(component.with_content("Escrowed listing with a copper accent border."))
      end
    end
  end
end
