# frozen_string_literal: true

module Shared
  module Alert
    class AlertComponentPreview < ViewComponent::Preview
      def error
        render(AlertComponent.new(tone: :error).with_content("Fix the fields marked below to continue."))
      end

      def info
        component = AlertComponent.new(tone: :info, title: "Every transaction is escrowed.")
        render(component.with_content("Funds lock at request and release only on delivery."))
      end

      def note
        render(AlertComponent.new(tone: :note).with_content("Your nsec never leaves your signer."))
      end

      def success
        render(AlertComponent.new(tone: :success).with_content("Listing published."))
      end
    end
  end
end
