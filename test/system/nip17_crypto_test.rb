# frozen_string_literal: true

require "application_system_test_case"

# Drives the real browser NIP-17 crypto against the SAME fixture the Ruby spine passes
# (test/services/messages/unwrap_test.rb), proving the JS and Ruby implementations are byte-aligned
# in both directions, and that the signer adapter drives the flow. The crypto modules use importmap
# bare specifiers that only resolve in a real module graph, so the test bridge is injected as a real
# <script type="module"> (see ApplicationSystemTestCase#load_nostr_bridge) and called via window.NostrCryptoTest.
class Nip17CryptoTest < ApplicationSystemTestCase
	VECTOR = JSON.parse(Rails.root.join("test/fixtures/files/nip59.vector.json").read).freeze

	def setup
		visit root_path
		load_nostr_bridge
	end

	test "unwrap recovers the NIP-59 published rumor (Ruby -> JS interop)" do
		result = evaluate_async_script(<<~JS, VECTOR["recipient_private_key"], VECTOR["gift_wrap"])
    const done = arguments[arguments.length - 1]
    const { NsecSigner, unwrap } = window.NostrCryptoTest
    unwrap(arguments[1], NsecSigner.fromHex(arguments[0]))
    	.then((rumor) => done(JSON.stringify(rumor)))
    	.catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "unwrap failed: #{result}")

		rumor = JSON.parse(result)
		expected = VECTOR["expected_rumor"]
		assert_equal expected["id"], rumor["id"]
		assert_equal expected["pubkey"], rumor["pubkey"]
		assert_equal expected["created_at"], rumor["created_at"]
		assert_equal expected["kind"], rumor["kind"]
		assert_equal expected["content"], rumor["content"]
		assert_equal expected["tags"], rumor["tags"]
		assert_equal %w[content created_at id kind pubkey tags], rumor.keys.sort, "only the canonical fields"
	end

	test "the JS canonical id matches the Ruby ComputeCanonicalId (rumor id recomputes)" do
		computed = evaluate_async_script(<<~JS, VECTOR["expected_rumor"])
    const done = arguments[arguments.length - 1]
    done(window.NostrCryptoTest.eventId(arguments[0]))
		JS
		assert_equal VECTOR["expected_rumor"]["id"], computed
	end

	test "round-trips a built message in the browser (seal/wrap then unwrap)" do
		result = evaluate_async_script(<<~JS)
    const done = arguments[arguments.length - 1]
    const { NsecSigner, buildRumor, wrapMessage, unwrap } = window.NostrCryptoTest
    ;(async () => {
    	const sender = NsecSigner.generate()
    	const recipient = NsecSigner.generate()
    	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "gm from the browser", recipients: [recipient.getPublicKey()] })
    	const { toRecipient, toSelf } = await wrapMessage(rumor, sender, recipient.getPublicKey())
    	const got = await unwrap(toRecipient, recipient)
    	const mine = await unwrap(toSelf, sender)
    	return JSON.stringify({ got, mine, senderPub: sender.getPublicKey(), rumorId: rumor.id })
    })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "round-trip failed: #{result}")

		data = JSON.parse(result)
		assert_equal "gm from the browser", data["got"]["content"]
		assert_equal data["senderPub"], data["got"]["pubkey"]
		assert_equal data["rumorId"], data["got"]["id"]
		assert_equal "gm from the browser", data["mine"]["content"], "the sender's own self-copy decrypts too"
	end

	test "a browser-built wrap is readable by the Ruby Unwrap (JS -> Ruby interop)" do
		recipient = Nostr::Keygen.new.generate_key_pair
		built = evaluate_async_script(<<~JS, recipient.public_key.to_s)
    const recipientPub = arguments[0]
    const done = arguments[arguments.length - 1]
    const { NsecSigner, buildRumor, wrapMessage } = window.NostrCryptoTest
    ;(async () => {
    	const sender = NsecSigner.generate()
    	const rumor = buildRumor({ authorPubkey: sender.getPublicKey(), content: "sealed in the browser", recipients: [recipientPub] })
    	const { toRecipient } = await wrapMessage(rumor, sender, recipientPub)
    	return JSON.stringify({ wrap: toRecipient, senderPub: sender.getPublicKey(), rumorId: rumor.id })
    })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, built, "browser build failed: #{built}")

		data = JSON.parse(built)
		rumor = Messages::Unwrap.call(gift_wrap: data["wrap"], recipient_private_key: recipient.private_key.to_s)
		assert_equal "sealed in the browser", rumor["content"]
		assert_equal data["senderPub"], rumor["pubkey"]
		assert_equal data["rumorId"], rumor["id"]
	end

	test "Nip07Signer drives the keyless crypto through window.nostr" do
		result = evaluate_async_script(<<~JS)
    const done = arguments[arguments.length - 1]
    const { Nip07Signer, NsecSigner, buildRumor, wrapMessage, unwrap } = window.NostrCryptoTest
    ;(async () => {
    	const backing = NsecSigner.generate()
    	window.nostr = {
    		getPublicKey: () => backing.getPublicKey(),
    		signEvent: (t) => backing.signEvent(t),
    		nip44: { encrypt: (pk, pt) => backing.nip44Encrypt(pk, pt), decrypt: (pk, ct) => backing.nip44Decrypt(pk, ct) },
    	}
    	const sender = new Nip07Signer()
    	const recipient = NsecSigner.generate()
    	const senderPub = await sender.getPublicKey()
    	const rumor = buildRumor({ authorPubkey: senderPub, content: "via the extension", recipients: [recipient.getPublicKey()] })
    	const { toRecipient } = await wrapMessage(rumor, sender, recipient.getPublicKey())
    	const got = await unwrap(toRecipient, recipient)
    	return JSON.stringify({ content: got.content, pubkey: got.pubkey, senderPub, canEncrypt: sender.canEncrypt() })
    })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "Nip07Signer flow failed: #{result}")

		data = JSON.parse(result)
		assert_equal "via the extension", data["content"]
		assert_equal data["senderPub"], data["pubkey"]
		assert data["canEncrypt"], "Nip07Signer.canEncrypt should feature-detect window.nostr.nip44"
	end
end
