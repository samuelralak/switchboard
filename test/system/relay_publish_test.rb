# frozen_string_literal: true

require "application_system_test_case"

# Cross-language wire-format contract for the NIP-65 relay-list publisher: the JS buildRelayListEvent builds
# the kind-10002 and the REAL Ruby Users::RelayListUpsert projects it, so the r-tag marker contract (an
# unmarked tag is read+write; a "read"/"write" marker restricts it) can never silently drift. Pure (no
# relays, no sign-in): build + sign in the browser, then project through the server read path.
class RelayPublishTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the JS-built kind-10002 read/write markers project correctly through RelayListUpsert" do
		json = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRelayListEvent } = window.NostrCryptoTest
		  const rows = [
		    { url: "wss://both.test", read: true, write: true },
		    { url: "wss://write.test", read: false, write: true },
		    { url: "wss://read.test", read: true, write: false },
		  ]
		  Promise.resolve(NsecSigner.generate().signEvent(buildRelayListEvent(rows)))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRelayListEvent/sign failed: #{json}")
		rows = project(json)

		both = rows.find_by(url: "wss://both.test")
		write_only = rows.find_by(url: "wss://write.test")
		read_only = rows.find_by(url: "wss://read.test")

		assert both.read && both.write, "an unmarked r-tag is both read + write"
		assert write_only.write && !write_only.read, "a write-marked r-tag is write-only"
		assert read_only.read && !read_only.write, "a read-marked r-tag is read-only"
	end

	test "non-canonical url variants are normalized to the server form and deduped to one r-tag" do
		json = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRelayListEvent } = window.NostrCryptoTest
		  const rows = [
		    { url: "wss://Relay.Example.COM/", read: true, write: true }, // uppercase host + trailing slash
		    { url: "wss://relay.example.com", read: false, write: true },  // already canonical, same relay
		  ]
		  Promise.resolve(NsecSigner.generate().signEvent(buildRelayListEvent(rows)))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRelayListEvent/sign failed: #{json}")
		r_tags = JSON.parse(json)["tags"].select { |tag| tag[0] == "r" }

		assert_equal 1, r_tags.size, "the casing/trailing-slash variant collapses into the canonical relay"
		assert_equal "wss://relay.example.com", r_tags.first[1], "emitted in the server's canonical form"
	end

	test "a row with neither role is dropped, and the kind-10002 content is empty" do
		json = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRelayListEvent } = window.NostrCryptoTest
		  const rows = [
		    { url: "wss://keep.test", read: true, write: true },
		    { url: "wss://drop.test", read: false, write: false },
		  ]
		  Promise.resolve(NsecSigner.generate().signEvent(buildRelayListEvent(rows)))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRelayListEvent/sign failed: #{json}")
		event = JSON.parse(json)

		assert_equal Events::Kinds::RELAY_LIST, event["kind"]
		assert_equal "", event["content"], "NIP-65 content is empty"
		assert_equal [ "wss://keep.test" ], project(json).pluck(:url), "a read=false write=false row is never published"
	end

	private

	# Store the JS-signed kind-10002 as the pubkey's winner, then project it through the real upsert.
	def project(json)
		event = JSON.parse(json)
		Event.create!(
			event_id: event["id"], pubkey: event["pubkey"], sig: event["sig"], kind: event["kind"],
			content: event["content"], tags: event["tags"], nostr_created_at: Time.zone.at(event["created_at"]),
			raw_event: event
		)
		Users::RelayListUpsert.call(event_data: event)
		UserRelay.where(pubkey: event["pubkey"])
	end
end

# Drives the real relay-form Stimulus controller on the settings page: it hydrates the row list from the
# prefill (the seeds, until a NIP-65 list is ingested) and supports add + remove. Signs in with a stubbed
# NIP-07 extension (same path as RequestFormTest); the publish/sign path is covered by RelayPublishTest.
class RelayEditorTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
		sign_in
	end

	test "hydrates the seed rows, then adds and removes a relay" do
		visit settings_relays_path
		assert_selector "form#relay-form"
		assert_selector "[data-relay-form-target='row']", count: 3 # the three seed relays prefill the editor

		find("[data-relay-form-target='newUrl']").set("wss://my.relay.test")
		click_button "Add"

		assert_selector "[data-relay-form-target='row']", count: 4
		assert_text "my.relay.test" # the new row shows the scheme-stripped host

		within all("[data-relay-form-target='row']").last do
			find("button[aria-label='Remove relay']").click
		end

		assert_selector "[data-relay-form-target='row']", count: 3
		assert_no_text "my.relay.test"
	end

	test "rejects a non-ws relay URL without adding a row" do
		visit settings_relays_path
		assert_selector "[data-relay-form-target='row']", count: 3

		find("[data-relay-form-target='newUrl']").set("http://not-a-relay.test")
		click_button "Add"

		assert_text "starts with wss://"
		assert_selector "[data-relay-form-target='row']", count: 3 # unchanged
	end

	private

	def sign_in
		execute_script(<<~JS)
		  const backing = window.NostrCryptoTest.NsecSigner.generate()
		  window.nostr = { getPublicKey: () => backing.getPublicKey(), signEvent: (t) => backing.signEvent(t) }
		JS
		click_button "Sign in"
		click_button "Browser extension"
		assert_text "Provider studio"
	end
end
