# frozen_string_literal: true

require "application_system_test_case"

# RelaySet resilience over the mock relay: re-subscribing after a reactive auth-required CLOSED, and the
# honest connectivity signal (subscribeMany().connected rejects when no relay opens) that lets the UI
# avoid a silent false-positive "Connected.".
class RelayResilienceTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
		page.driver.browser.manage.timeouts.script_timeout = 20 # the reconnect test waits out a backoff
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

	test "subscribeMany reconnects after a non-auth drop and resumes delivering" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const wrapFor = async (text) => {
		  		const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: text, recipients: [recipient.getPublicKey()] })
		  		return (await wrapMessage(rumor, sender, recipient.getPublicKey())).toRecipient
		  	}
		  	const first = await wrapFor("before drop"), second = await wrapFor("after drop")
		  	const [server] = installMockRelays([{ url: "wss://flap.test", seed: [first] }])
		  	const set = new RelaySet(["wss://flap.test"], { signer: recipient })
		  	let events = 0, degraded = 0, reopened = 0
		  	const filter = [{ kinds: [1059], "#p": [recipient.getPublicKey()] }]
		  	const sub = set.subscribeMany(filter, { onevent: () => { events++ } })
		  	sub.addEventListener("relay-degraded", () => { degraded++ })
		  	sub.addEventListener("relay-reopened", () => { reopened++ })
		  	await sub.connected
		  	const waitFor = async (cond, ms) => { const end = Date.now() + ms; while (!cond() && Date.now() < end) await new Promise((r) => setTimeout(r, 50)) }
		  	await waitFor(() => events >= 1, 1000) // the seeded event is delivered
		  	server.store(second)  // available to the reconnected REQ
		  	server.dropSockets()  // server-initiated, non-auth close
		  	await waitFor(() => events >= 2 && reopened >= 1, 8000) // reconnect backoff + re-subscribe + redeliver
		  	sub.close(); set.close()
		  	return JSON.stringify({ events, degraded, reopened })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "reconnect failed: #{result}")
		data = JSON.parse(result)
		assert_equal 2, data["events"], "the pre-drop AND the post-reconnect event are both delivered"
		assert_operator data["degraded"], :>=, 1, "a relay-degraded event fires on the drop"
		assert_operator data["reopened"], :>=, 1, "a relay-reopened event fires on reconnect"
	end

	test "the liveness probe reconnects a silently half-open (black-holed) relay" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	if (document.visibilityState !== "visible") return "SKIP: headless tab is not visible; probe is visibility-gated"
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "seed", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	const [server] = installMockRelays([{ url: "wss://silent.test", seed: [toRecipient] }])
		  	const set = new RelaySet(["wss://silent.test"], { signer: recipient, probeAfter: 400, probeTimeout: 400 })
		  	let degraded = 0
		  	const sub = set.subscribeMany([{ kinds: [1059], "#p": [recipient.getPublicKey()] }], {})
		  	sub.addEventListener("relay-degraded", () => { degraded++ })
		  	await sub.connected
		  	server.blackhole = true // socket stays OPEN but answers nothing: a silent half-open
		  	const end = Date.now() + 4000
		  	while (degraded < 1 && Date.now() < end) await new Promise((r) => setTimeout(r, 100))
		  	sub.close(); set.close()
		  	return JSON.stringify({ degraded })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		skip(result.delete_prefix("SKIP: ")) if result.to_s.start_with?("SKIP:")
		assert_no_match(/\AERR:/, result, "probe failed: #{result}")
		assert_operator JSON.parse(result)["degraded"], :>=, 1, "the probe detects the silent socket and reconnects"
	end

	test "publishToMany reports timeout (not error) when an open relay never acks" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "x", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	installMockRelays([{ url: "wss://slowack.test", withholdOk: true }]) // open, stores, never OKs
		  	const set = new RelaySet(["wss://slowack.test"], { signer: sender, publishTimeout: 1500 })
		  	const results = await set.publishToMany(toRecipient)
		  	set.close()
		  	return JSON.stringify(results.map((r) => r.status))
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "publish failed: #{result}")
		assert_equal [ "timeout" ], JSON.parse(result), "an open-but-unacking relay surfaces as timeout (possibly delivered), not error"
	end

	test "a post-auth publish that never acks reports timeout (not error) on an AUTH-gated relay" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "x", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	installMockRelays([{ url: "wss://gatedslow.test", authRequired: true, withholdOk: true }]) // AUTHs, then never OKs
		  	const set = new RelaySet(["wss://gatedslow.test"], { signer: sender, publishTimeout: 1500 })
		  	const results = await set.publishToMany(toRecipient)
		  	set.close()
		  	return JSON.stringify(results.map((r) => r.status))
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "publish failed: #{result}")
		assert_equal [ "timeout" ], JSON.parse(result), "the post-auth retry timeout must be timeout, not error (money-safe on gated relays)"
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
