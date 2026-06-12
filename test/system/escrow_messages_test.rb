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

	# The Tier-2 happy-path wire contract: doReleaseTier2 ships the consumer-co-signed proofs to the provider as
	# a 'cosign' message; doRedeemTier2 reads them back via latestEscrowMessage(type 'cosign'). Lock the shape
	# (the proofs array, witnesses intact) so a field-name/round-trip regression cannot ship silently.
	test "a cosign message round-trips the consumer's signed proofs to the provider" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowMessages: em, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const consumer = NsecSigner.generate(), provider = NsecSigner.generate()
		  	const cPub = consumer.getPublicKey(), pPub = provider.getPublicKey()
		  	const proofs = [{ id: "00ad", amount: 4, secret: "s1", C: "02c1", witness: JSON.stringify({ signatures: ["aa"] }) }]
		  	await em.sendEscrowMessage({ signer: consumer, ownPubkey: cPub, peerPubkey: pPub, relays, orderId: "ord-1", type: "cosign", data: { proofs } })
		  	const got = await em.latestEscrowMessage({ signer: provider, ownPubkey: pPub, relays, orderId: "ord-1", type: "cosign", from: cPub })
		  	const p = got && got.data && got.data.proofs && got.data.proofs[0]
		  	return JSON.stringify({ type: got && got.type, n: got && got.data && got.data.proofs.length, amount: p && p.amount, witness: p && p.witness, secret: p && p.secret })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "cosign round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal "cosign", data["type"]
		assert_equal 1, data["n"], "the provider reads back the proofs array"
		assert_equal 4, data["amount"], "the proof amount survives the round-trip (numeric, not corrupted)"
		assert_equal "s1", data["secret"], "the proof secret survives"
		assert_equal({ "signatures" => [ "aa" ] }.to_json, data["witness"], "the consumer's witness signature survives")
	end
end
