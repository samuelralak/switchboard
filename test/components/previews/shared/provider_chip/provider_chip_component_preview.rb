# frozen_string_literal: true

module Shared
  module ProviderChip
    class ProviderChipComponentPreview < ViewComponent::Preview
      def default
        render(ProviderChipComponent.new(name: "Apollo", npub: "npub1apollo7x9q"))
      end

      def long_name_truncates
        render(ProviderChipComponent.new(name: "Mercury Messaging Collective", npub: "npub1mercury42z"))
      end
    end
  end
end
