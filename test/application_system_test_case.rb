# frozen_string_literal: true

require "test_helper"

# Drives the real importmap JS in headless Chrome (Capybara + Selenium). Used to vector-test the
# browser NIP-17 crypto against the same fixtures the Ruby spine uses, so the two stay byte-aligned.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
	driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

	# Injects the keyless-crypto test bridge (app/javascript/test_support/test_support.js, pinned as
	# "nostr/test_support" outside production) as a real module script -- its imports resolve via the page
	# import map, unlike an executeScript dynamic import -- and records any in-page error for diagnostics.
	NOSTR_BRIDGE_JS = <<~JS
   if (!window.__nostrBridge) {
   	window.__nostrBridge = true
   	window.__nostrErr = null
   	window.addEventListener("error", (e) => { window.__nostrErr = String((e && e.message) || (e && e.error)) })
   	window.addEventListener("unhandledrejection", (e) => { window.__nostrErr = String(e.reason && (e.reason.message || e.reason)) })
   	const imports = JSON.parse(document.querySelector('script[type="importmap"]').textContent).imports
   	const script = document.createElement("script")
   	script.type = "module"
   	script.src = imports["nostr/test_support"]
   	script.addEventListener("error", () => { window.__nostrErr = "test_support failed to load: " + script.src })
   	document.head.appendChild(script)
   }
	JS

	# turbo-rails patches #visit to wait for every <turbo-cable-stream-source> to report [connected].
	# Turbo Cable is not wired for system tests, so that wait errors on the catalog's live-update
	# stream source. These tests exercise client-side crypto, not Turbo Cable, so skip the wait.
	def connect_turbo_cable_stream_sources(*) = nil

	# Inject the crypto bridge, then poll (Ruby-side, no async-script timeout) for window.NostrCryptoTest.
	def load_nostr_bridge
		execute_script(NOSTR_BRIDGE_JS)
		20.times do
			return if evaluate_script("typeof window.NostrCryptoTest") == "object"

			sleep 0.5
		end
		flunk("crypto bridge did not load; in-page error: #{evaluate_script('window.__nostrErr')}")
	end
end
