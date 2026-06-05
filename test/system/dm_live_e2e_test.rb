# frozen_string_literal: true

require "application_system_test_case"

# REAL relay interop against wss://auth.nostr1.com (the server's configured dm_relays). Env-gated so it
# NEVER runs in default CI -- network, relay availability, and AUTH policy are non-deterministic.
#   SWITCHBOARD_LIVE_E2E=1 bin/rails test test/system/dm_live_e2e_test.rb
# Proves the real NIP-42 AUTH handshake (user-signed kind-22242), real publish OK-correlation with the
# auth-required re-publish, real subscribe delivery of the kind-1059, and unwrap to plaintext. A failure
# here while the mock-relay CI tests are green is most likely relay policy (recipient-restriction /
# kind-10050 requirement) or network -- a relay/topology signal, not a code regression.
class DmLiveE2eTest < ApplicationSystemTestCase
	RELAY = "wss://auth.nostr1.com"

	def setup
		skip "set SWITCHBOARD_LIVE_E2E=1 to run the live relay e2e" unless ENV["SWITCHBOARD_LIVE_E2E"]
		visit root_path
		load_nostr_bridge
	end

	# Fire-and-forget the flow into the page (stashing state on window.__live) and poll from Ruby, so the
	# long real-relay round trip never trips the Selenium async-script timeout.
	test "a real gift wrap delivers through auth.nostr1.com end to end" do
		execute_script(LIVE_FLOW, RELAY)

		state = nil
		40.times do
			state = evaluate_script("window.__live")
			flunk("live e2e error: #{state['error']}") if state && state["error"]
			break if state && state["received"] && !state["received"].empty?

			sleep 1
		end

		assert state, "the flow never initialized"
		assert_includes state["received"], state["ping"], "the recipient received + unwrapped the live DM"
	end

	LIVE_FLOW = <<~JS
	  const relay = arguments[0]
	  window.__live = { received: [], ping: null, error: null }
	  ;(async () => {
	  	const { NsecSigner, DmClient } = window.NostrCryptoTest
	  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
	  	const rc = new DmClient({ signer: recipient, relays: [relay], onMessage: (r) => window.__live.received.push(r.content) })
	  	const sc = new DmClient({ signer: sender, relays: [relay] })
	  	await rc.start()
	  	await sc.start()
	  	window.__live.ping = "switchboard live e2e " + Date.now()
	  	await sc.send(recipient.getPublicKey(), window.__live.ping)
	  })().catch((e) => { window.__live.error = String((e && e.message) || e) })
	JS
end
