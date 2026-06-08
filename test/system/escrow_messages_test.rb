# frozen_string_literal: true

require "application_system_test_case"

# The escrow handshake over NIP-17 (escrow_messages.js): the consumer delivers the locked proofs and
# reveals the preimage to the provider, order-scoped and end-to-end encrypted. Mock relay; no mint.
class EscrowMessagesTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the consumer delivers proofs + reveals the preimage; the provider reads them, order-scoped" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowMessages: em, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const consumer = NsecSigner.generate(), provider = NsecSigner.generate()
		  	const cPub = consumer.getPublicKey(), pPub = provider.getPublicKey()
		  	const base = { signer: consumer, ownPubkey: cPub, peerPubkey: pPub, relays }
		  	await em.sendEscrowMessage({ ...base, orderId: "ord-1", type: "token-delivery", data: { proofs: [{ amount: 8 }] } })
		  	await em.sendEscrowMessage({ ...base, orderId: "ord-1", type: "preimage-reveal", data: { preimage: "ab".repeat(32) } })
		  	await em.sendEscrowMessage({ ...base, orderId: "ord-2", type: "token-delivery", data: { proofs: [{ amount: 1 }] } })
		  	const forOrder1 = await em.fetchEscrowMessages({ signer: provider, ownPubkey: pPub, relays, orderId: "ord-1" })
		  	const reveal = await em.latestEscrowMessage({ signer: provider, ownPubkey: pPub, relays, orderId: "ord-1", type: "preimage-reveal", from: cPub })
		  	return JSON.stringify({ count: forOrder1.length, types: forOrder1.map((m) => m.type), fromConsumer: forOrder1.every((m) => m.from === cPub), revealed: reveal && reveal.data.preimage })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "handshake failed: #{result}")
		data = JSON.parse(result)

		assert_equal 2, data["count"], "the provider reads exactly the two ord-1 messages (ord-2 filtered out)"
		assert_equal %w[token-delivery preimage-reveal], data["types"], "messages are typed, oldest-first"
		assert data["fromConsumer"], "each message is attributed to the consumer's pubkey"
		assert_equal ("ab" * 32), data["revealed"], "the latest preimage-reveal carries the preimage"
	end
end
