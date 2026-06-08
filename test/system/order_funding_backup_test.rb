# frozen_string_literal: true

require "application_system_test_case"

# The consumer's durable backup of an order's unlock material (order_funding.js): a fast local copy
# (IndexedDB) plus a NIP-44-self-encrypted NIP-17 wrap on relays, recoverable on another device. The Y
# values Rails stores cannot rebuild a spendable token, so this backup is what keeps a funded order
# releasable/refundable. No mint here; the mock relay carries the self-DM.
class OrderFundingBackupTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "escrow secrets are kept locally and in an encrypted self-DM, then restored from the relay" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, orderFunding: of, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const owner = NsecSigner.generate()
		  	const pub = owner.getPublicKey()
		  	const secrets = { token: "cashuAtoken", preimage: "ab".repeat(32), mint: "http://m.test", locktime: 1718000000 }
		  	await of.backupSecrets({ signer: owner, ownPubkey: pub, relays, orderId: "order-1", secrets })
		  	const local = await of.loadSecrets("order-1")
		  	const fromRelay = await of.restoreSecretsFromRelay({ signer: owner, ownPubkey: pub, relays, orderId: "order-1" })
		  	return JSON.stringify({ local, fromRelay })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "backup round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal "cashuAtoken", data.dig("local", "token"), "the local copy keeps the token"
		assert_equal "cashuAtoken", data.dig("fromRelay", "token"), "the self-DM restores the token"
		assert_equal ("ab" * 32), data.dig("fromRelay", "preimage"), "the self-DM restores the preimage"
	end

	# Funds-safety: a relay-failed backup must keep the local copy (with its report payload) so a retry
	# resumes from the existing lock instead of re-minting and overwriting it.
	test "a relay-failed backup still keeps the local copy for a safe resume" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, orderFunding: of, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://down.test", fail: true }])
		  	const relays = ["wss://down.test"]
		  	const owner = NsecSigner.generate()
		  	const secrets = { token: "cashuBdown", preimage: "cd".repeat(32), mint: "http://m.test", locktime: 1718000000, payload: { hashlock: "x" } }
		  	let threw = false
		  	try {
		  		await of.backupSecrets({ signer: owner, ownPubkey: owner.getPublicKey(), relays, orderId: "order-2", secrets })
		  	} catch (_) { threw = true }
		  	const local = await of.loadSecrets("order-2")
		  	return JSON.stringify({ threw, localToken: local && local.token, hasPayload: Boolean(local && local.payload) })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "failed-relay backup test errored: #{result}")
		data = JSON.parse(result)

		assert data["threw"], "a backup that reaches no relay surfaces an error"
		assert_equal "cashuBdown", data["localToken"], "the local copy survives the relay failure"
		assert data["hasPayload"], "the stored copy carries the report payload so a resume can re-submit"
	end
end
