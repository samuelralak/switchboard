# frozen_string_literal: true

# Per-request identity (Rails 8 auth pattern), reset after each request. The browser path
# sets `session` (Authentication#resume_session); the stateless API path sets
# `authenticated_user` (Nip98Authentication#authenticate_request!).
class Current < ActiveSupport::CurrentAttributes
	attribute :session, :authenticated_user

	def user
		authenticated_user || session&.user
	end
end
