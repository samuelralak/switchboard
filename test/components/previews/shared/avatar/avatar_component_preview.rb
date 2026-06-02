# frozen_string_literal: true

module Shared
  module Avatar
    class AvatarComponentPreview < ViewComponent::Preview
      def default
        render(AvatarComponent.new(seed: "npub1apollo7x9q"))
      end

      def large_rounded
        render(AvatarComponent.new(seed: "npub1apollo7x9q", size: 64, rounded: :lg))
      end

      def without_ring
        render(AvatarComponent.new(seed: "npub1mercury42z", size: 40, ring: false))
      end
    end
  end
end
