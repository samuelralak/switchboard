# frozen_string_literal: true

require "test_helper"

module Layout
	module IdentityMenu
		class IdentityMenuComponentTest < ViewComponent::TestCase
			def test_signed_out_shows_a_sign_in_button_that_opens_the_dialog
				render_inline(IdentityMenuComponent.new(user: nil))

				assert_selector "button[commandfor='signin-dialog']", text: "Sign in"
				assert_text "Browser extension"
			end

			def test_signed_in_shows_the_truncated_npub_and_account_menu
				user = User.new(pubkey: "a" * 64)
				render_inline(IdentityMenuComponent.new(user:))

				assert_text user.npub[0, 8]
				assert_selector "a", text: "Your profile"
				assert_text "Disconnect signer"
			end
		end
	end
end
