# frozen_string_literal: true

require "test_helper"

module Settings
	module Shell
		class ShellComponentTest < ViewComponent::TestCase
			Routes = Rails.application.routes.url_helpers

			test "highlights the active section, links the others, and yields the body" do
				render_inline(ShellComponent.new(active: :profile)) { "BODY CONTENT" }

				assert_text "BODY CONTENT"
				assert_selector "a[href='#{Routes.settings_profile_path}'][aria-current='page']", text: "Profile"
				assert_selector "a[href='#{Routes.settings_relays_path}']", text: "Relays"
			end

			test "renders coming-soon sections as non-links" do
				render_inline(ShellComponent.new(active: :relays)) { "x" }

				assert_no_link "Signer"
				assert_no_link "Notifications"
				assert_text "Soon"
				assert_selector "a[href='#{Routes.settings_relays_path}'][aria-current='page']", text: "Relays"
			end
		end
	end
end
