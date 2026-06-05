# frozen_string_literal: true

require "application_system_test_case"

# Drives the DmClient engine (signer + RelaySet + cold-start cache) over the in-page mock relay: a real
# send/receive round trip, the anonymous /inbox deposit (asserted against the DB), and the client-side
# size guard. Adversarial paths (forged-wrap discard, capability gating) are in dm_security_test; the
# Stimulus DOM wrapper in direct_messages_controller_test; real-relay interop in the live e2e.
class DmRoundTripTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "two clients round-trip a message: recipient receives it, sender sees its own copy" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, DmClient, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://dm.test", authRequired: false }])
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const received = [], mine = []
		  	const rc = new DmClient({ signer: recipient, relays: ["wss://dm.test"], onMessage: (r) => received.push(r.content) })
		  	const sc = new DmClient({ signer: sender, relays: ["wss://dm.test"], onMessage: (r) => mine.push(r.content) })
		  	await rc.start(); await sc.start()
		  	await sc.send(recipient.getPublicKey(), "hello over the wire")
		  	await new Promise((r) => setTimeout(r, 500))
		  	rc.stop(); sc.stop()
		  	return JSON.stringify({ received, mine })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "round-trip failed: #{result}")

		data = JSON.parse(result)
		assert_equal [ "hello over the wire" ], data["received"], "recipient receives the DM over the relay"
		assert_includes data["mine"], "hello over the wire", "sender sees its own self-copy"
	end

	test "send deposits the recipient's wrap to the anonymous cold-start cache" do
		recipient_pub = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, DmClient, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://dm.test", authRequired: false }])
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const sc = new DmClient({ signer: sender, relays: ["wss://dm.test"], inboxUrl: "/inbox" })
		  	await sc.start()
		  	await sc.send(recipient.getPublicKey(), "cached for cold start")
		  	sc.stop()
		  	return recipient.getPublicKey()
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, recipient_pub, "deposit failed: #{recipient_pub}")

		assert_equal 1, InboxWrap.count, "the recipient copy is deposited to the cache"
		assert_equal recipient_pub, InboxWrap.sole.recipient_pubkey
		assert_equal 1059, InboxWrap.sole.wrap["kind"]
	end

	# Both the cheap pre-check (raw content over the cap) AND the double-wrap overflow (a payload under the
	# raw cap whose seal re-encryption overflows the outer nip44) surface one clean "message too long".
	test "oversized messages are rejected before publish, and nothing is deposited" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, DmClient, installMockRelays } = window.NostrCryptoTest
		  const send = (sc, n) => sc.send(NsecSigner.generate().getPublicKey(), "a".repeat(n)).then(() => "NO_THROW").catch((e) => e.message)
		  ;(async () => {
		  	installMockRelays([{ url: "wss://dm.test", authRequired: false }])
		  	const sc = new DmClient({ signer: NsecSigner.generate(), relays: ["wss://dm.test"], inboxUrl: "/inbox" })
		  	await sc.start()
		  	return JSON.stringify({ raw: await send(sc, 65536), overflow: await send(sc, 50000) })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "oversize test failed: #{result}")

		data = JSON.parse(result)
		assert_equal "message too long", data["raw"], "raw content over the cap is rejected by the pre-check"
		assert_equal "message too long", data["overflow"], "the double-wrap overflow surfaces the same clean error"
		assert_equal 0, InboxWrap.count, "an over-limit message never reaches the cache"
	end
end
