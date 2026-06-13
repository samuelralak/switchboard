# frozen_string_literal: true

require "test_helper"

module Layout
	module Sidebar
		class SidebarComponentTest < ViewComponent::TestCase
			def test_renders_brand_navigation_relays_and_footer
				render_inline(Layout::Sidebar::SidebarComponent.new)

				assert_text "Switchboard"
				assert_selector "a", text: "Catalog"
				assert_selector "a", text: "Orders"
				assert_no_selector "a", text: "Provider studio" # moved to the top-bar CTA
				assert_text "relay.damus.io"
				assert_selector "a", text: "Manage" # links to the relays settings page (no modal)

				# Static footer links replace the old Settings link (Settings now lives in the identity menu).
				assert_no_selector "a", text: "Settings"
				assert_selector "a", text: "GitHub"
				assert_selector "a", text: "Contact"
				assert_selector "a", text: "Terms & privacy"
				assert_selector "a", text: "Donate"
			end
		end
	end
end
