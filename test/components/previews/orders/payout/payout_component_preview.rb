# frozen_string_literal: true

module Orders
	module Payout
		class PayoutComponentPreview < ViewComponent::Preview
			# Hidden by default in production (the settlement controller reveals + fills it); the screenshot script
			# un-hides and fills it to verify the craft.
			def default
				render(PayoutComponent.new)
			end
		end
	end
end
