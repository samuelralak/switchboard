# frozen_string_literal: true

module Layout
	module IdentityMenu
		# Top-bar identity menu: a "Sign in" button when signed out, or the connected npub
		# with a dropdown of account actions when signed in.
		class IdentityMenuComponent < ApplicationComponent
			def initialize(user: nil)
				@user = user
			end

			def signed_in? = @user.present?

			# The connected npub, truncated to a prefix and suffix for display.
			def display_npub
				npub = @user.npub
				npub.length <= 14 ? npub : "#{npub[0, 8]}…#{npub[-4..]}"
			end

			def menu_items
				[
					{ label: "Your profile",  href: "#" },
					{ label: "Your listings", href: "#" }
				]
			end
		end
	end
end
