# frozen_string_literal: true

require "application_system_test_case"

# Relay round trips for the escrow identity (nostr/escrow_identity.js) over the in-page mock relay:
# ensure -> discover -> restore, concurrent-setup coalescing, the client-side author guard against a
# non-compliant relay, and malformed-backup fallback. Pure wire-format contracts live in
# escrow_identity_test. Rails never sees the private key (brief sec 6.3).
class EscrowIdentityRelayTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "ensure publishes backup + ad, a counterparty discovers it, the owner restores it" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowIdentity: ei, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const provider = NsecSigner.generate()
		  	const acct = provider.getPublicKey()
		  	const id1 = await ei.ensureEscrowIdentity({ accountPubkey: acct, signer: provider, relays, mints: ["https://m.test"] })
		  	const id2 = await ei.ensureEscrowIdentity({ accountPubkey: acct, signer: provider, relays, mints: ["https://m.test"] })
		  	const found = await ei.discover(acct, relays)
		  	const recovered = await ei.restoreFromWallet(acct, provider, relays)
		  	return JSON.stringify({ id1, id2, found, recovered })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "ensure/discover/restore failed: #{result}")
		data = JSON.parse(result)

		assert_match(/\A0[23][0-9a-f]{64}\z/, data.dig("id1", "pubkeyHex"))
		assert_equal data.dig("id1", "pubkeyHex"), data.dig("id2", "pubkeyHex"), "a second ensure returns the cached key"
		assert_equal data.dig("id1", "pubkeyHex"), data.dig("found", "pubkey"), "discovered pubkey matches advertised"
		assert_equal [ "https://m.test" ], data.dig("found", "mints")
		assert_equal data.dig("id1", "privkeyHex"), data.dig("recovered", "privkeyHex"), "restored privkey matches"
	end

	test "concurrent ensure calls coalesce to one key and one backup" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowIdentity: ei, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	const servers = installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const provider = NsecSigner.generate()
		  	const opts = { accountPubkey: provider.getPublicKey(), signer: provider, relays, mints: ["https://m.test"] }
		  	const [a, b] = await Promise.all([ei.ensureEscrowIdentity(opts), ei.ensureEscrowIdentity(opts)])
		  	const backups = servers[0].events.filter((e) => e.kind === 17375).length
		  	return JSON.stringify({ a: a.pubkeyHex, b: b.pubkeyHex, backups })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "concurrent ensure failed: #{result}")
		data = JSON.parse(result)

		assert_equal data["a"], data["b"], "both concurrent callers get the same key"
		assert_equal 1, data["backups"], "only one kind:17375 backup is published"
	end

	test "discover rejects a kind:10019 forged by a different author, even from a non-compliant relay" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, RelaySet, escrowIdentity: ei, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false, enforceAuthors: false }])
		  	const relays = ["wss://e.test"]
		  	const provider = NsecSigner.generate(), attacker = NsecSigner.generate()
		  	const victimKey = ei.newEscrowKey()
		  	const forged = await attacker.signEvent(ei.buildInfoEvent({ pubkeyHex: victimKey.pubkeyHex, mints: [], relays }))
		  	const set = new RelaySet(relays, { signer: attacker })
		  	await set.publishToMany(forged); set.close()
		  	const found = await ei.discover(provider.getPublicKey(), relays)
		  	return JSON.stringify({ forgedAuthor: forged.pubkey, providerPub: provider.getPublicKey(), found })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "forged-author test failed: #{result}")
		data = JSON.parse(result)

		assert_not_equal data["forgedAuthor"], data["providerPub"], "the forged event is signed by the attacker"
		assert_nil data["found"], "discover ignores a 10019 whose author is not the queried pubkey"
	end

	test "a malformed kind:17375 backup is discarded and ensure generates a fresh key" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, RelaySet, escrowIdentity: ei, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://e.test", authRequired: false }])
		  	const relays = ["wss://e.test"]
		  	const owner = NsecSigner.generate()
		  	const acct = owner.getPublicKey()
		  	const content = await owner.nip44Encrypt(acct, JSON.stringify([["privkey", "not-a-valid-key"]]))
		  	const bad = await owner.signEvent({ kind: 17375, created_at: Math.floor(Date.now() / 1000), content, tags: [] })
		  	const set = new RelaySet(relays, { signer: owner })
		  	await set.publishToMany(bad); set.close()
		  	const restored = await ei.restoreFromWallet(acct, owner, relays)
		  	const id = await ei.ensureEscrowIdentity({ accountPubkey: acct, signer: owner, relays, mints: [] })
		  	return JSON.stringify({ restored, pub: id.pubkeyHex })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "malformed-backup test failed: #{result}")
		data = JSON.parse(result)

		assert_nil data["restored"], "a malformed backup is discarded, not surfaced"
		assert_match(/\A0[23][0-9a-f]{64}\z/, data["pub"], "ensure falls back to a freshly generated key")
	end
end
