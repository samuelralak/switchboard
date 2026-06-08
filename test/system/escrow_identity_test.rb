# frozen_string_literal: true

require "application_system_test_case"

# Pure wire-format contracts for the per-account Cashu escrow identity (nostr/escrow_identity.js): a
# secp256k1 P2PK key SEPARATE from the Nostr key (NIP-07/bunker cannot raw-sign a proof secret), the
# NIP-61 kind:10019 advertisement, and the NIP-60 kind:17375 encrypted-to-self backup. No relays here;
# the ensure/discover/restore round trips live in escrow_identity_relay_test. Rails never sees the
# private key (brief sec 6.3).
class EscrowIdentityTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "an escrow keypair derives a stable 02/03-prefixed compressed pubkey" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { escrowIdentity: ei } = window.NostrCryptoTest
		  const k = ei.newEscrowKey()
		  done(JSON.stringify({ priv: k.privkeyHex, pub: k.pubkeyHex, derived: ei.pubkeyForPrivkey(k.privkeyHex) }))
		JS
		data = JSON.parse(result)

		assert_match(/\A[0-9a-f]{64}\z/, data["priv"], "privkey is 64-hex")
		assert_match(/\A0[23][0-9a-f]{64}\z/, data["pub"], "pubkey is 66-hex SEC1-compressed")
		assert_equal data["pub"], data["derived"], "the pubkey deterministically re-derives from the privkey"
	end

	test "the kind:10019 advertisement round-trips through build, sign, and parse" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowIdentity: ei } = window.NostrCryptoTest
		  ;(async () => {
		  	const signer = NsecSigner.generate()
		  	const key = ei.newEscrowKey()
		  	const tmpl = ei.buildInfoEvent({ pubkeyHex: key.pubkeyHex, mints: ["https://m.test"], relays: ["wss://r.test"] })
		  	const signed = await signer.signEvent(tmpl)
		  	return JSON.stringify({ kind: signed.kind, author: signed.pubkey, pub: key.pubkeyHex, parsed: ei.parseInfoEvent(signed) })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "10019 round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal 10_019, data["kind"]
		assert_equal data["pub"], data.dig("parsed", "pubkey"), "advertised P2PK pubkey survives the round trip"
		assert_not_equal data["author"], data.dig("parsed", "pubkey"), "escrow pubkey is not the Nostr key (NIP-61)"
		assert_equal [ "https://m.test" ], data.dig("parsed", "mints")
		assert_equal [ "wss://r.test" ], data.dig("parsed", "relays")
	end

	test "parseInfoEvent rejects a 10019 whose pubkey is not a SEC1-compressed key" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowIdentity: ei } = window.NostrCryptoTest
		  ;(async () => {
		  	const signer = NsecSigner.generate()
		  	const signed = await signer.signEvent({ kind: 10019, created_at: Math.floor(Date.now() / 1000),
		  		content: "", tags: [["pubkey", "not-a-real-key"]] })
		  	return JSON.stringify({ parsed: ei.parseInfoEvent(signed) })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "malformed-pubkey test failed: #{result}")

		assert_nil JSON.parse(result)["parsed"], "a non-conformant escrow pubkey is rejected, never locked to"
	end

	test "the kind:17375 backup encrypts the privkey to self, restores it, and a stranger cannot read it" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, escrowIdentity: ei } = window.NostrCryptoTest
		  ;(async () => {
		  	const owner = NsecSigner.generate(), stranger = NsecSigner.generate()
		  	const acct = owner.getPublicKey()
		  	const key = ei.newEscrowKey()
		  	const signed = await owner.signEvent(await ei.buildWalletEvent(owner, acct, { privkeyHex: key.privkeyHex, mints: ["https://m.test"] }))
		  	const restored = await ei.parseWalletEvent(owner, acct, signed)
		  	const strangerGot = await ei.parseWalletEvent(stranger, acct, signed)
		  	return JSON.stringify({ kind: signed.kind, content: signed.content, expected: key.privkeyHex, restored, strangerGot })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "17375 round-trip failed: #{result}")
		data = JSON.parse(result)

		assert_equal 17_375, data["kind"]
		assert_not_includes data["content"], data["expected"], "privkey is encrypted, not plaintext"
		assert_equal data["expected"], data.dig("restored", "privkeyHex"), "the owner recovers the exact privkey"
		assert_equal [ "https://m.test" ], data.dig("restored", "mints")
		assert_nil data["strangerGot"], "a non-owner signer cannot decrypt the backup"
	end
end
