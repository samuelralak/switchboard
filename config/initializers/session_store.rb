# frozen_string_literal: true

# Cookie flags for the Rails session (used for flash + the CSRF token). The revocable
# sign-in session id lives in its own signed cookie (see the Authentication concern).
Rails.application.config.session_store(
	:cookie_store,
	key: "_switchboard_session",
	httponly: true,
	secure: Rails.env.production?,
	same_site: :lax
)
