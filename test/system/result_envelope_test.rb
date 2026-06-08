# frozen_string_literal: true

require "application_system_test_case"

# The delivered result over NIP-17 (result_envelope.js): the provider seals the finished work to the
# consumer, order-scoped and end-to-end encrypted, joined to the listing by an `a` tag. The consumer trusts
# it only when its author is the order's provider. Mock relay; no mint.
class ResultEnvelopeTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the provider seals the result; the consumer reads it, order-scoped and author-checked" do
		result = evaluate_async_script(round_trip_js)
		assert_no_match(/\AERR:/, result, "result round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal 3, data["total"], "the consumer decrypts all three wraps addressed to them"
		assert_equal "3 findings. 1 blocking.", data["result"], "the trusted result carries the delivered work"
		assert_equal "https://blossom.example/x.png", data["attachment"], "and an attachment reference"
		assert_equal "deadbeef", data["hash"], "with its content hash"
		assert data["coordinate"].start_with?("30402:"), "the listing coordinate is joined by the `a` tag"
		assert data["from"], "the trusted result is attributed to the provider, not the attacker"
		assert data["forgedRejected"], "the attacker's result matches only under the attacker anchor, never the provider"
	end

	private

	# Provider seals two orders' results + an attacker forges one for ord-1; the consumer reads ord-1 only
	# when the trust anchor is the real provider.
	def round_trip_js
		<<~JS
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, resultEnvelope: re, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://r.test", authRequired: false }])
		  	const relays = ["wss://r.test"]
		  	const provider = NsecSigner.generate(), consumer = NsecSigner.generate(), attacker = NsecSigner.generate()
		  	const pPub = provider.getPublicKey(), cPub = consumer.getPublicKey()
		  	const coordinate = "30402:" + pPub + ":svc"
		  	const attachments = [{ url: "https://blossom.example/x.png", hash: "deadbeef", name: "x.png" }]
		  	await re.sendResultEnvelope({ signer: provider, ownPubkey: pPub, peerPubkey: cPub, relays,
		  		orderId: "ord-1", coordinate, result: "3 findings. 1 blocking.", attachments, note: "see inline" })
		  	await re.sendResultEnvelope({ signer: provider, ownPubkey: pPub, peerPubkey: cPub, relays,
		  		orderId: "ord-2", coordinate, result: "other" })
		  	await re.sendResultEnvelope({ signer: attacker, ownPubkey: attacker.getPublicKey(), peerPubkey: cPub, relays,
		  		orderId: "ord-1", coordinate, result: "forged" })

		  	const all = await re.fetchResultEnvelopes({ signer: consumer, ownPubkey: cPub, relays })
		  	const trusted = await re.latestResultEnvelope({ signer: consumer, ownPubkey: cPub, relays, orderId: "ord-1", provider: pPub })
		  	const forged = await re.latestResultEnvelope({ signer: consumer, ownPubkey: cPub, relays, orderId: "ord-1", provider: attacker.getPublicKey() })
		  	return JSON.stringify({
		  		total: all.length, result: trusted && trusted.result, attachment: trusted && trusted.attachments[0].url,
		  		hash: trusted && trusted.attachments[0].hash, coordinate: trusted && trusted.coordinate,
		  		from: trusted && trusted.from === pPub, forgedRejected: forged !== null && forged.result === "forged",
		  	})
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
	end
end
