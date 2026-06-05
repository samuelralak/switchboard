# frozen_string_literal: true

require "application_system_test_case"

# DmClient cold-start must follow the keyset cursor across pages: a backlog larger than one page is
# fully ingested, not silently truncated at page one. Drives a stubbed paginated /inbox so the loop is
# exercised deterministically (the server-side keyset paging itself is covered by inbox_controller_test).
class DmColdStartTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "cold-start follows the cursor and ingests every page, not just the first" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, DmClient, buildRumor, wrapMessage, installMockRelays } = window.NostrCryptoTest
		  ;(async () => {
		  	installMockRelays([{ url: "wss://dm.test", authRequired: false }])
		  	const sender = NsecSigner.generate(), recipient = NsecSigner.generate(), pub = recipient.getPublicKey()
		  	const wrapFor = async (t) => (await wrapMessage(buildRumor({ authorPubkey: sender.getPublicKey(), content: t, recipients: [pub] }), sender, pub)).toRecipient
		  	const pages = [{ wraps: [await wrapFor("page one")], cursor: "c1" }, { wraps: [await wrapFor("page two")], cursor: "c2" }, { wraps: [], cursor: null }]
		  	let i = 0
		  	const realFetch = window.fetch
		  	window.fetch = async () => ({ ok: true, json: async () => pages[Math.min(i++, pages.length - 1)] })
		  	const got = []
		  	const client = new DmClient({ signer: recipient, relays: ["wss://dm.test"], inboxUrl: "/inbox", onMessage: (r) => got.push(r.content) })
		  	try { await client.start() } finally { window.fetch = realFetch; client.stop() }
		  	return JSON.stringify({ got })
		  })().then(done).catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_no_match(/\AERR:/, result, "cold-start pagination failed: #{result}")
		assert_equal [ "page one", "page two" ], JSON.parse(result)["got"], "every cold-start page is ingested"
	end
end
