# frozen_string_literal: true

module Layout
	module IdentityMenu
		class IdentityMenuComponentPreview < ViewComponent::Preview
			def signed_out
				render(IdentityMenuComponent.new(user: nil))
			end

			def signed_in
				render(IdentityMenuComponent.new(user: User.new(pubkey: "a" * 64)))
			end
		end
	end
end
