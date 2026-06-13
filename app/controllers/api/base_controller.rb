# frozen_string_literal: true

module Api
	# Base for stateless JSON endpoints authenticated per request by a NIP-98
	# `Authorization: Nostr` header. Identity comes only from authenticate_request!; there
	# is no cookie session, so CSRF does not apply.
	class BaseController < ApplicationController
		include Nip98Authentication

		skip_forgery_protection
		rate_limit to: 60, within: 1.minute, by: -> { client_ip }
	end
end
