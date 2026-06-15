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

			def test_signed_in_shows_an_avatar_dropdown_with_account_actions
				user = User.new(pubkey: "a" * 64)
				render_inline(IdentityMenuComponent.new(user:))

				assert_selector "img" # identicon fallback (no kind-0 picture)
				assert_text user.npub[0, 8]
				assert_selector "a", text: "Your profile"
				assert_selector "a", text: "Settings"
				assert_text "Disconnect signer"
			end

			def test_signed_in_with_a_picture_uses_it_as_the_avatar
				user = User.new(pubkey: "a" * 64, picture: "https://example.com/avatar.png")
				render_inline(IdentityMenuComponent.new(user:))

				assert_selector "img[src='https://example.com/avatar.png']"
			end

			def test_an_operator_gets_an_admin_link
				user = User.new(pubkey: "a" * 64)
				with_operator(user.pubkey) do
					render_inline(IdentityMenuComponent.new(user:))
				end

				assert_selector "a[href='#{Rails.application.routes.url_helpers.admin_disputes_path}']", text: "Admin"
			end

			def test_a_non_operator_has_no_admin_link
				user = User.new(pubkey: "a" * 64)
				with_operator("b" * 64) do
					render_inline(IdentityMenuComponent.new(user:))
				end

				assert_no_selector "a", text: "Admin"
			end

			private

			def with_operator(pubkey)
				saved = Rails.application.config.x.operator_pubkeys
				Rails.application.config.x.operator_pubkeys = [ pubkey ]
				yield
			ensure
				Rails.application.config.x.operator_pubkeys = saved
			end
		end
	end
end
