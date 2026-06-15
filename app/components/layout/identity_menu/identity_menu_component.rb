# frozen_string_literal: true

module Layout
	module IdentityMenu
		# Top-bar identity: a "Sign in" button when signed out, or a compact avatar (kind-0 picture, or a
		# pubkey identicon fallback) with a dropdown of account actions when signed in.
		class IdentityMenuComponent < ApplicationComponent
			include IdenticonHelper

			def initialize(user: nil)
				@user = user
			end

			def signed_in? = @user.present?

			def picture = @user.picture.presence

			delegate :pubkey, to: :@user

			# A human label for the dropdown header: display name, then name, then the short npub.
			def display_label
				@user.display_name.presence || @user.name.presence || display_npub
			end

			def nip05 = @user.nip05.presence

			# The connected npub, truncated to a prefix and suffix for display.
			def display_npub
				npub = @user.npub
				npub.length <= 14 ? npub : "#{npub[0, 8]}…#{npub[-4..]}"
			end

			def menu_items
				[
					{ label: "Your profile", href: helpers.profile_path(npub: @user.npub) },
					{ label: "Settings", href: helpers.settings_path }
				]
			end

			# Operators get a separate link into the admin surface (disputes/flags/settings).
			def operator? = Operator.authorized?(@user.pubkey)

			def admin_path = helpers.admin_disputes_path
		end
	end
end
