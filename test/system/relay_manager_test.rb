# frozen_string_literal: true

require "application_system_test_case"

# Drives the real nostr-tools Relay + our RelaySet manager against an in-page mock relay (a fake
# WebSocket scripting NIP-01/42 frames), so the load-bearing glue -- auth-required re-publish,
# cross-relay dedup, single EOSE -- is proven deterministically and offline. The live-relay proof is
# the separate, env-gated dm_live_e2e_test.
class RelayManagerTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "publishToMany resolves ok on an open relay and after NIP-42 auth on a gated relay" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([
		  		{ url: "wss://open.test", authRequired: false },
		  		{ url: "wss://gated.test", authRequired: true },
		  	])
		  	const sender = NsecSigner.generate()
		  	const recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "hi", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	const set = new RelaySet(["wss://open.test", "wss://gated.test"], { signer: sender })
		  	const results = await set.publishToMany(toRecipient)
		  	set.close()
		  	return JSON.stringify(results)
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "publish failed: #{result}")

		results = JSON.parse(result)
		assert_equal %w[ok ok], results.pluck("status"), "both relays accept after auth"
		assert_equal %w[wss://gated.test wss://open.test], results.pluck("url").sort
	end

	test "subscribeMany dedups the same wrap from two relays to one onevent and fires eose once" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRumor, wrapMessage, RelaySet, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "dup", recipients: [recipient.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
		  	const seed = [toRecipient]
		  	installMockRelays([{ url: "wss://a.test", authRequired: false, seed }, { url: "wss://b.test", authRequired: false, seed }])
		  	const set = new RelaySet(["wss://a.test", "wss://b.test"], { signer: recipient })
		  	let events = 0, eoses = 0
		  	await new Promise((resolve) => {
		  		const filter = [{ kinds: [1059], "#p": [recipient.getPublicKey()] }]
		  		set.subscribeMany(filter, { onevent: () => { events++ }, oneose: () => { eoses++ } })
		  		setTimeout(resolve, 800)
		  	})
		  	set.close()
		  	return JSON.stringify({ events, eoses })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "subscribe failed: #{result}")

		data = JSON.parse(result)
		assert_equal 1, data["events"], "the same wrap from two relays is delivered once (cross-relay dedup)"
		assert_equal 1, data["eoses"], "aggregate EOSE fires exactly once"
	end
end
