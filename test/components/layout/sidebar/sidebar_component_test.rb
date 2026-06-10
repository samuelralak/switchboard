# frozen_string_literal: true

require "test_helper"

module Layout
	module Sidebar
		class SidebarComponentTest < ViewComponent::TestCase
			def test_renders_brand_navigation_relays_and_settings
				render_inline(Layout::Sidebar::SidebarComponent.new)

				assert_text "Switchboard"
				assert_selector "a", text: "Catalog"
				assert_selector "a", text: "My requests"
				assert_no_selector "a", text: "Provider studio" # moved to the top-bar CTA
				assert_text "relay.damus.io"
				assert_selector "a", text: "Manage" # links to the relays settings page (no modal)
				assert_selector "a", text: "Settings"
			end
		end
	end
end
