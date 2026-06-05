# frozen_string_literal: true

require "application_system_test_case"

# The DmClient's adversarial paths: a wrap not addressed to me is discarded (UnwrapError, never
# rendered), and the NIP-44 capability self-test gates a signer that cannot actually encrypt.
class DmSecurityTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "a wrap not addressed to me is discarded, not rendered" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, DmClient, buildRumor, wrapMessage, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://dm.test", authRequired: false }])
		  	const me = NsecSigner.generate(), sender = NsecSigner.generate(), stranger = NsecSigner.generate()
		  	const got = []
		  	const client = new DmClient({ signer: me, relays: ["wss://dm.test"], onMessage: (r) => got.push(r.content) })
		  	await client.start()
		  	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "not for you", recipients: [stranger.getPublicKey()] })
		  	const { toRecipient } = await wrapMessage(rumor, sender, stranger.getPublicKey())
		  	await client.ingest(toRecipient) // encrypted to the stranger; I cannot decrypt it
		  	client.stop()
		  	return JSON.stringify({ count: got.length })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "discard test failed: #{result}")
		assert_equal 0, JSON.parse(result)["count"], "an undecryptable wrap is silently discarded"
	end

	test "canMessage gates on a working NIP-44 round-trip" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, canMessage } = window.NostrCryptoTest
		  ;(async () => {
		  	const real = await canMessage(NsecSigner.generate())
		  	const noNip44 = await canMessage({ canEncrypt: () => false })
		  	const throwing = await canMessage({
		  		canEncrypt: () => true,
		  		getPublicKey: () => "f".repeat(64),
		  		nip44Encrypt: () => { throw new Error("bunker lacks nip44 permission") },
		  		nip44Decrypt: () => "x",
		  	})
		  	return JSON.stringify({ real, noNip44, throwing })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "capability test failed: #{result}")

		data = JSON.parse(result)
		assert data["real"], "a locally-held key can always encrypt"
		assert_not data["noNip44"], "a signer without nip44 is gated out"
		assert_not data["throwing"], "a signer whose encrypt throws (no runtime grant) is gated out"
	end
end
