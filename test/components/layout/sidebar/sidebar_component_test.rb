# frozen_string_literal: true

require "test_helper"

module Layout
	module Sidebar
		class SidebarComponentTest < ViewComponent::TestCase
			def test_renders_brand_navigation_and_relays
				render_inline(Layout::Sidebar::SidebarComponent.new)

				assert_text "Switchboard"
				assert_selector "a", text: "Catalog"
				assert_selector "a", text: "My requests"
				assert_selector "a", text: "Provider studio"
				assert_text "relay.damus.io"
			end
		end
	end
end
