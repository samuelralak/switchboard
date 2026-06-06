# frozen_string_literal: true

require "application_system_test_case"

# Cross-language wire-format contract for the non-custodial publisher (#65): the JS buildEvents builds the
# kind-30402 and the REAL Ruby Catalog::Listing reads it back, so the publisher can never silently drift
# from the read contract. Pure (no relays, no sign-in): just buildEvents + the Ruby read model.
class ListingBuildEventsTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the JS-built kind-30402 is read back correctly by Catalog::Listing (wire-format contract)" do
		json = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildEvents } = window.NostrCryptoTest
		  const data = {
		    title: "Summarize a thread", description: "Tight summaries.", capability: "summarize", price: "120",
		    fulfillment: "automated", endpoint: "https://api.example.com/fulfill", dTag: "fixed-d",
		    schema: [{ name: "src", label: "Source", type: "longtext", required: true }],
		    images: [{ url: "https://h/a.png", m: "image/png", x: "abc", dim: "800x450" }],
		  }
		  const { listing } = buildEvents(data, { marker, capabilityNamespace, origin: "https://sb.test" })
		  Promise.resolve(NsecSigner.generate().signEvent(listing))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildEvents/sign failed: #{json}")
		listing = listing_from(json)

		assert_equal "Summarize a thread", listing.title
		assert_equal "summarize", listing.capability
		assert_equal 120, listing.price_amount
		assert_equal "automated", listing.fulfillment
		assert_equal "https://api.example.com/fulfill", listing.endpoint
		assert_predicate listing, :conforms?
		assert_equal([ { name: "src", label: "Source", type: "longtext", required: true } ], listing.input_schema)
		assert_equal [ "https://h/a.png" ], listing.images
		assert_equal({ url: "https://h/a.png", m: "image/png", x: "abc", dim: "800x450" }, listing.image_meta("https://h/a.png"))
	end

	test "a per-hour listing carries the NIP-99 hour frequency and reads back as per_hour" do
		json = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildEvents } = window.NostrCryptoTest
		  const data = { title: "Consulting", capability: "consult", price: "50000", priceFrequency: "hour", dTag: "c" }
		  const { listing } = buildEvents(data, { marker, capabilityNamespace, origin: "https://sb.test" })
		  Promise.resolve(NsecSigner.generate().signEvent(listing))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildEvents/sign failed: #{json}")
		listing = listing_from(json)

		assert_equal 50_000, listing.price_amount
		assert_equal "hour", listing.price_frequency
		assert_predicate listing, :per_hour?
		assert_equal "sat / hr", listing.price_suffix
	end

	test "buildEvents carries status + published_at on edit and bumps created_at past the prior version" do
		json = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { buildEvents } = window.NostrCryptoTest
		  const data = { title: "T", capability: "c", price: "1", dTag: "keep-d", status: "inactive", publishedAt: "555", createdAt: "1000" }
		  const { listing } = buildEvents(data, { marker, capabilityNamespace, origin: "https://sb.test" })
		  done(JSON.stringify(listing))
		JS
		event = JSON.parse(json)
		tag = ->(key) { event["tags"].find { |t| t[0] == key }&.dig(1) }

		assert_equal "inactive", tag.call("status"), "an edit of an inactive listing stays inactive"
		assert_equal "555", tag.call("published_at"), "the original publish date is preserved"
		assert_equal "keep-d", tag.call("d"), "re-publishes under the same coordinate"
		assert_operator event["created_at"], :>, 1000, "created_at is bumped past the prior version to supersede"
	end

	test "buildEvents throws on a missing required field so a malformed listing can never be signed" do
		result = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { buildEvents } = window.NostrCryptoTest
		  const config = { marker, capabilityNamespace, origin: "https://sb.test" }
		  const out = {}
		  try { buildEvents({ title: "", capability: "c", price: "1" }, config); out.title = "NO THROW" }
		  catch (e) { out.title = e.message }
		  try { buildEvents({ title: "T", capability: "", price: "1" }, config); out.capability = "NO THROW" }
		  catch (e) { out.capability = e.message }
		  try { buildEvents({ title: "T", capability: "c", price: "0" }, config); out.price = "NO THROW" }
		  catch (e) { out.price = e.message }
		  out.ok = buildEvents({ title: "T", capability: "c", price: "1" }, config).listing.kind
		  done(JSON.stringify(out))
		JS
		out = JSON.parse(result)

		assert_match(/title/, out["title"], "an empty title must throw")
		assert_match(/capability/, out["capability"], "an empty capability must throw")
		assert_match(/price/, out["price"], "a non-positive price must throw")
		assert_equal 30_402, out["ok"], "a complete listing still builds the kind-30402"
	end

	private

	# Read the signed wire event (JSON) back through the real Ruby read model.
	def listing_from(json)
		e = JSON.parse(json)
		event = Event.new(kind: e["kind"], pubkey: e["pubkey"], content: e["content"], tags: e["tags"])
		Catalog::Listing.new(event)
	end
end

# Broadcast round-trips through a mock relay (signed by a generated key, no sign-in needed): the unpublish
# status flip + NIP-09 handler withdrawal, the latest-version re-fetch, and the full publish (kind-30402 +
# kind-31990).
class ListingPublishTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "unpublishing flips the listing to inactive and broadcasts a NIP-09 deletion of the handler" do
		result = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, installMockRelays, setListingStatus, RelaySet } = window.NostrCryptoTest
		  installMockRelays([{ url: "wss://pub.test" }])
		  const event = { kind: 30402, content: "x", created_at: 1000,
		    tags: [["d", "d1"], ["title", "T"], ["t", marker], ["l", "c", capabilityNamespace], ["status", "active"]] }
		  const config = { marker, capabilityNamespace, origin: "https://sb.test" }
		  setListingStatus(event, "inactive", config, NsecSigner.generate(), ["wss://pub.test"]).then(async (res) => {
		    const events = []
		    const set = new RelaySet(["wss://pub.test"])
		    await new Promise((r) => {
		      set.subscribeMany([{ kinds: [30402, 5] }], { onevent: (e) => events.push({ kind: e.kind, status: (e.tags.find((t) => t[0] === "status") || [])[1] }), oneose: r })
		      setTimeout(r, 600)
		    })
		    set.close()
		    done(JSON.stringify({ reached: res.reached, events }))
		  }).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, result, "setListingStatus failed: #{result}")

		data = JSON.parse(result)
		assert_operator data["reached"], :>=, 1
		listing = data["events"].find { |e| e["kind"] == 30_402 }
		assert_equal "inactive", listing["status"], "the listing is flipped to inactive"
		assert(data["events"].any? { |e| e["kind"] == 5 }, "a NIP-09 deletion withdraws the handler announcement")
	end

	test "setListingStatus flips the LATEST version of the coordinate, not a stale render-time snapshot" do
		result = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, installMockRelays, setListingStatus, RelaySet } = window.NostrCryptoTest
		  installMockRelays([{ url: "wss://pub.test" }])
		  const signer = NsecSigner.generate()
		  const config = { marker, capabilityNamespace, origin: "https://sb.test" }
		  const base = (createdAt, content) => ({ kind: 30402, content, created_at: createdAt,
		    tags: [["d", "d1"], ["title", "T"], ["t", marker], ["l", "c", capabilityNamespace], ["price", "1", "sat"], ["status", "active"]] })
		  ;(async () => {
		    // Seed a NEWER version (another tab's edit) on the relay, then unpublish from a STALE snapshot.
		    const newer = await signer.signEvent(base(2000, "edited in another tab"))
		    const set = new RelaySet(["wss://pub.test"], { signer })
		    await set.publishToMany(newer)
		    set.close()
		    const res = await setListingStatus(base(1000, "stale snapshot"), "inactive", config, signer, ["wss://pub.test"])
		    return JSON.stringify({ content: res.event.content, status: (res.event.tags.find((t) => t[0] === "status") || [])[1] })
		  })().then(done).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, result, "setListingStatus failed: #{result}")

		data = JSON.parse(result)
		assert_equal "edited in another tab", data["content"], "the flip is applied to the re-fetched latest version"
		assert_equal "inactive", data["status"], "and its status is flipped"
	end

	test "broadcastListing publishes both the listing and the handler announcement to the relays" do
		result = evaluate_async_script(<<~JS, Catalog::Listing.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, installMockRelays, broadcastListing, RelaySet } = window.NostrCryptoTest
		  installMockRelays([{ url: "wss://pub.test" }])
		  const data = { title: "T", capability: "c", price: "10", fulfillment: "manual", deliveryWindow: "24h", dTag: "d1" }
		  broadcastListing(data, { marker, capabilityNamespace, origin: "https://sb.test" }, NsecSigner.generate(), ["wss://pub.test"])
		    .then(async (res) => {
		      const kinds = []
		      const set = new RelaySet(["wss://pub.test"])
		      await new Promise((resolve) => {
		        set.subscribeMany([{ kinds: [30402, 31990] }], { onevent: (e) => kinds.push(e.kind), oneose: resolve })
		        setTimeout(resolve, 600)
		      })
		      set.close()
		      done(JSON.stringify({ reached: res.reached, coordinate: res.coordinate, kinds }))
		    }).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, result, "broadcast failed: #{result}")

		data = JSON.parse(result)
		assert_operator data["reached"], :>=, 1, "listing reached at least one relay"
		assert_match(/\A30402:.+:d1\z/, data["coordinate"], "the coordinate uses the supplied d-tag")
		assert_includes data["kinds"], 30_402, "the NIP-99 listing landed on the relay"
		assert_includes data["kinds"], 31_990, "the NIP-89 handler announcement landed on the relay"
	end
end

# The full UI publish flow: fill the studio form, sign with the held nsec key, and see the receipt.
class ListingStudioPublishTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "filling the studio form and publishing shows the success receipt" do
		sign_in_with_nsec
		click_link "Provider studio"
		click_link "Publish a service", match: :first # header CTA + empty-state CTA both match on the empty index
		assert_text "No code runs on Switchboard" # the new-listing form's subtitle

		execute_script(<<~JS)
		  window.NostrCryptoTest.installMockRelays([
		    { url: "wss://relay.damus.io" }, { url: "wss://relay.nostr.band" }, { url: "wss://nos.lol" }
		  ])
		JS

		fill_in "title", with: "Summarize a thread"
		fill_in "capability", with: "summarize"
		fill_in "price", with: "120"
		fill_in "delivery_value", with: "24" # manual is the default fulfillment mode now
		click_button "Sign & publish listing"

		assert_text "Listing published"
		assert_text "30402:" # the coordinate is shown on the receipt
	end

	private

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_text "Provider studio"
	end
end
