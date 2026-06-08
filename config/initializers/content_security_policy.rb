# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Application-wide Content Security Policy. script-src is same-origin plus the jsdelivr CDN
# (the lazy-loaded nostr-tools modules and their +esm dependency rewrites) plus a per-request
# nonce, with no unsafe-inline, so an injected inline script is refused. style-src allows
# inline because the vendored Tailwind Plus Elements components style inline. connect-src is
# open to https and wss because a Nostr client reaches arbitrary user-chosen relays (wss) and
# NIP-05 domains (https); img-src allows https for remote profile pictures.
Rails.application.configure do
	config.content_security_policy do |policy|
		# Non-prod-only: the escrow system test drives cashu-ts in-browser against the local HTTP mint
		# (http://127.0.0.1:3338); production mints are HTTPS, already covered by :https below.
		mint_local = Rails.env.production? ? [] : %w[http://127.0.0.1:3338 http://localhost:3338]
		policy.default_src     :self
		policy.base_uri        :self
		policy.object_src      :none
		policy.frame_ancestors :none
		policy.form_action     :self
		policy.script_src      :self, "https://cdn.jsdelivr.net"
		policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.hugeicons.com"
		policy.font_src        :self, :data, "https://fonts.gstatic.com", "https://cdn.hugeicons.com"
		policy.img_src         :self, :data, :https
		policy.connect_src     :self, :https, "wss:", *mint_local
	end

	# Per-session nonce: javascript_importmap_tags stamps it on its inline scripts automatically,
	# and csp_meta_tag exposes it so Turbo can re-nonce scripts it injects on navigation. Stored in
	# the session (NOT request.session.id, which is EMPTY for a visitor with no session yet -> an
	# empty "nonce-" that blocks EVERY inline script, including the importmap and the JS entry point,
	# leaving a fresh visitor with no client JS at all). SecureRandom keeps it non-empty; ||= keeps
	# it stable across the session so a restored Turbo page still matches.
	config.content_security_policy_nonce_generator = lambda do |request|
		request.session[:csp_nonce] ||= SecureRandom.base64(16)
	end
	config.content_security_policy_nonce_directives = %w[script-src]
end
