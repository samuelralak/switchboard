# frozen_string_literal: true

module Layout
  module Sidebar
    class SidebarComponentPreview < ViewComponent::Preview
      def default
        render(Layout::Sidebar::SidebarComponent.new)
      end
    end
  end
end
