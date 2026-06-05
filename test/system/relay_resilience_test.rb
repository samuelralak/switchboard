# frozen_string_literal: true

require "application_system_test_case"

# RelaySet resilience over the mock relay: re-subscribing after a reactive auth-required CLOSED, and the
# honest connectivity signal (subscribeMany().connected rejects when no relay opens) that lets the UI
# avoid a silent false-positive "Connected.".
class RelayResilienceTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "subscribeMany re-subscribes after a reactive auth-required CLOSED, then delivers" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "after auth", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	installMockRelays([{ url: "wss://gated.test", authRequired: true, proactiveAuth: false, seed: [toRecipient] }])
		  	const set = new RelaySet(["wss://gated.test"], { signer: recipient })
		  	let events = 0
		  	const filter = [{ kinds: [1059], "#p": [recipient.getPublicKey()] }]
		  	set.subscribeMany(filter, { onevent: () => { events++ } })
		  	await new Promise((r) => setTimeout(r, 1200))
		  	set.close()
		  	return JSON.stringify({ events })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "re-subscribe failed: #{result}")
		assert_equal 1, JSON.parse(result)["events"], "the seeded wrap is delivered after the auth-required re-subscribe"
	end

	test "subscribeMany().connected rejects when no relays are configured" do
		rejected = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { RelaySet } = window.NostrCryptoTest
		  new RelaySet([], {}).subscribeMany([{ kinds: [1059] }], {}).connected
		  	.then(() => done(false)).catch(() => done(true))
		JS
		assert rejected, "an empty relay list must reject readiness, not silently succeed"
	end

	test "subscribeMany().connected rejects when every relay fails to connect" do
		rejected = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { RelaySet, installMockRelays } = window.NostrCryptoTest
		  installMockRelays([{ url: "wss://down.test", fail: true }])
		  new RelaySet(["wss://down.test"], {}).subscribeMany([{ kinds: [1059] }], {}).connected
		  	.then(() => done(false)).catch(() => done(true))
		JS
		assert rejected, "all-relays-down must reject readiness so the UI can show an honest error"
	end
end
