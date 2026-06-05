# frozen_string_literal: true

require "test_helper"

class CspNonceTest < ActionDispatch::IntegrationTest
	# Regression: a fresh visitor (no session yet) must still get a NON-EMPTY CSP script-src nonce.
	# An empty "nonce-" matches nothing, so the inline importmap and the JS entry point are blocked
	# and the entire client app is dead (Stimulus never starts, bare specifiers never resolve). The
	# old generator used request.session.id.to_s, which is empty until a session exists.
	test "a fresh request gets a non-empty script-src nonce stamped on the importmap and entry tags" do
		get root_path
		assert_response :success

		nonce = response.headers["Content-Security-Policy"].to_s[/script-src[^;]*'nonce-([^']+)'/, 1]
		assert nonce.present?, "CSP script-src nonce is empty: every inline script is blocked"

		escaped = Regexp.escape(nonce)
		assert_match(/<script type="importmap"[^>]*nonce="#{escaped}"/, response.body, "importmap missing nonce")
		assert_match(/<script type="module"[^>]*nonce="#{escaped}"/, response.body, "entry missing nonce")
	end

	# Regression: connect-src must allow wss: or the browser NIP-17 client (#32) cannot open a relay
	# socket at all -- every DM send/receive over wss:// would be blocked by the CSP.
	test "connect-src allows wss: relay connections" do
		get root_path
		assert_response :success

		connect_src = response.headers["Content-Security-Policy"].to_s[/connect-src[^;]*/]
		assert_includes connect_src.to_s, "wss:", "connect-src must permit wss:// relays for the NIP-17 client"
	end
end
