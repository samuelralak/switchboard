# frozen_string_literal: true

module Layout
	module IdentityMenu
		# Top-bar identity menu showing the connected npub and signer status with a
		# dropdown of account actions.
		class IdentityMenuComponent < ApplicationComponent
			def initialize(npub: "npub1you000000000000000000000000000000000000000000k4m2", signer: "key in signer")
				@npub = npub
				@signer = signer
			end

			attr_reader :signer

			# Returns the npub truncated to a prefix/suffix for display.
			def display_npub
				return @npub if @npub.length <= 14

				"#{@npub[0, 8]}…#{@npub[-4..]}"
			end

			def menu_items
				[
					{ label: "Your profile",      href: "#" },
					{ label: "Your listings",     href: "#" },
					{ label: "Disconnect signer", href: "#", separated: true }
				]
			end
		end
	end
end
