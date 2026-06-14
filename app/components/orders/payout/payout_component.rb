# frozen_string_literal: true

module Orders
	module Payout
		# The payee's claimable payout: hidden until the settlement Stimulus controller fills it with the
		# redeemed/refunded Cashu token (just settled, or restored from a local/relay backup). Pure markup with
		# data-settlement-target hooks, so it MUST render inside a `data-controller="settlement"` scope.
		class PayoutComponent < ApplicationComponent
		end
	end
end
