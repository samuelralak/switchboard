# frozen_string_literal: true

require "application_system_test_case"

# The order request over NIP-17 (order_envelope.js): the consumer seals the filled service inputs to the
# provider, order-scoped and end-to-end encrypted, joined to the listing by an `a` tag. Mock relay; no mint.
class OrderEnvelopeTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the consumer seals the filled inputs; the provider reads them, order-scoped and author-checked" do
		result = evaluate_async_script(round_trip_js)
		assert_no_match(/\AERR:/, result, "envelope round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal 3, data["total"], "the provider decrypts all three wraps addressed to them"
		assert_equal "Repository URL", data["label"], "the trusted request carries the filled schema label"
		assert_equal "https://example.com/repo", data["value"], "and its value"
		assert_equal "ship by friday", data["note"], "and the optional note"
		assert data["coordinate"].start_with?("30402:"), "the listing coordinate is joined by the `a` tag"
		assert data["coordinate"].end_with?(":svc"), "and carries the listing d-tag"
		assert data["from"], "the trusted request is attributed to the consumer, not the attacker"
		assert data["forgedRejected"], "an attacker's envelope matches only under the attacker anchor, never the consumer"
	end

	private

	# Consumer seals two orders' requests + an attacker forges one for ord-1; the provider reads ord-1 only
	# when the trust anchor is the real consumer.
	def round_trip_js
		<<~JS
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, orderEnvelope: oe, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://o.test", authRequired: false }])
		  	const relays = ["wss://o.test"]
		  	const consumer = NsecSigner.generate(), provider = NsecSigner.generate(), attacker = NsecSigner.generate()
		  	const cPub = consumer.getPublicKey(), pPub = provider.getPublicKey()
		  	const coordinate = "30402:" + pPub + ":svc"
		  	const inputs = [{ label: "Repository URL", value: "https://example.com/repo" }]
		  	await oe.sendOrderRequest({ signer: consumer, ownPubkey: cPub, peerPubkey: pPub, relays,
		  		orderId: "ord-1", coordinate, inputs, note: "ship by friday" })
		  	await oe.sendOrderRequest({ signer: consumer, ownPubkey: cPub, peerPubkey: pPub, relays,
		  		orderId: "ord-2", coordinate, inputs: [{ label: "x", value: "y" }] })
		  	await oe.sendOrderRequest({ signer: attacker, ownPubkey: attacker.getPublicKey(), peerPubkey: pPub, relays,
		  		orderId: "ord-1", coordinate, inputs: [{ label: "evil", value: "payload" }] })

		  	const all = await oe.fetchOrderRequests({ signer: provider, ownPubkey: pPub, relays })
		  	const trusted = await oe.latestOrderRequest({ signer: provider, ownPubkey: pPub, relays, orderId: "ord-1", consumer: cPub })
		  	const forged = await oe.latestOrderRequest({ signer: provider, ownPubkey: pPub, relays, orderId: "ord-1", consumer: attacker.getPublicKey() })
		  	return JSON.stringify({
		  		total: all.length, label: trusted && trusted.inputs[0].label, value: trusted && trusted.inputs[0].value,
		  		note: trusted && trusted.note, coordinate: trusted && trusted.coordinate, from: trusted && trusted.from === cPub,
		  		forgedRejected: forged !== null && forged.inputs[0].label === "evil",
		  	})
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
	end
end
