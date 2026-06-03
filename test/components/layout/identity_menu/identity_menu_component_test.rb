# frozen_string_literal: true

require "test_helper"

module Layout
	module IdentityMenu
		class IdentityMenuComponentTest < ViewComponent::TestCase
			def test_renders_truncated_npub_status_and_menu
				render_inline(Layout::IdentityMenu::IdentityMenuComponent.new(npub: "npub1abcd0000wxyz"))

				assert_text "npub1abc…wxyz"
				assert_text "key in signer"
				assert_selector "a", text: "Your profile"
				assert_selector "a", text: "Your listings"
				assert_selector "a", text: "Disconnect signer"
			end
		end
	end
end
