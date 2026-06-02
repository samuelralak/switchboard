# frozen_string_literal: true

module Shared
  module BackLink
    class BackLinkComponentPreview < ViewComponent::Preview
      def default
        render(BackLinkComponent.new(label: "catalog", href: "#"))
      end

      def custom_icon
        render(BackLinkComponent.new(label: "all listings", href: "#", icon: "arrow-left-02"))
      end
    end
  end
end
