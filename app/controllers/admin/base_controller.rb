# frozen_string_literal: true

module Admin
	# Session-authed platform-operator surface, gated by the OPERATOR_PUBKEYS allowlist (a Nostr login, not a DB
	# role). A logged-out or non-operator caller is sent home and never told the surface exists.
	class BaseController < ApplicationController
		include RedirectsOnError

		before_action :require_operator

		private

		def require_operator
			redirect_to(root_path) unless signed_in? && Operator.authorized?(current_user.pubkey)
		end
	end
end
