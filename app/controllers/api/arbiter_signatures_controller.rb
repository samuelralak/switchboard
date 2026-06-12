# frozen_string_literal: true

module Api
	# POST /api/orders/:order_id/arbiter_signatures -> the platform arbiter's detached signatures for the
	# winning party of a ruled Tier-2 dispute, so they can finish the 2-of-3 spend. The caller submits the proof
	# secrets and receives one BIP-340 signature per secret. Stateless JSON, NIP-98 authed (the Api convention):
	# never a Turbo/redirect response, so the controller stays consistent. The server signs only secrets bound
	# to THIS order's proofs and only for the party the ruling favours; every other case is an opaque 403.
	class ArbiterSignaturesController < BaseController
		before_action :authenticate_request!

		rescue_from(AuthorizationError) { head :forbidden }
		rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
		rescue_from(ActionController::ParameterMissing) { head :bad_request }

		def create
			order = Order.involving(Current.user.pubkey).find(params.expect(:order_id))
			signatures = Orders::ArbiterSign.call(order:, caller_pubkey: Current.user.pubkey, secrets: secret_params)

			render json: { signatures: }
		end

		private

		def secret_params
			params.expect(secrets: []).map(&:to_s)
		end
	end
end
