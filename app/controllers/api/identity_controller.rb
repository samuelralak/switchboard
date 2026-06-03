# frozen_string_literal: true

module Api
	# GET /api/identity -> the authenticated caller's pubkey/npub. Exercises the stateless
	# NIP-98 path and lets a client confirm the identity it is signing as.
	class IdentityController < BaseController
		before_action :authenticate_request!

		def show
			render json: { pubkey: Current.user.pubkey, npub: Current.user.npub }
		end
	end
end
