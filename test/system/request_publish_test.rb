# frozen_string_literal: true

require "application_system_test_case"

# Cross-language wire-format contract for the open-request publisher: the JS buildRequestEvent builds the
# kind-30402 and the REAL Ruby Requests::OpenRequest reads it back, so the publisher can never silently
# drift from the read contract. Pure (no relays, no sign-in): just buildRequestEvent + the Ruby read model.
class RequestBuildEventsTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "the JS-built kind-30402 request is read back correctly by Requests::OpenRequest" do
		json = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRequestEvent } = window.NostrCryptoTest
		  const data = { title: "Diagnose an engine", description: "From a video.", capability: "diagnosis",
		    budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "fixed-d" }
		  const { request } = buildRequestEvent(data, { marker, capabilityNamespace })
		  Promise.resolve(NsecSigner.generate().signEvent(request))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRequestEvent/sign failed: #{json}")
		request = request_from(json)

		assert_equal "Diagnose an engine", request.title
		assert_equal "diagnosis", request.capability
		assert_equal 5000, request.budget_amount
		assert_equal "24h", request.delivery_window
		assert_equal "3d", request.claim_window
		assert_predicate request, :conforms?
	end

	test "carries image + imeta tags read back by OpenRequest" do
		json = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRequestEvent } = window.NostrCryptoTest
		  const data = { title: "T", capability: "c", budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "d",
		    images: [{ url: "https://h/a.png", m: "image/png", x: "abc", dim: "800x450" }] }
		  const { request } = buildRequestEvent(data, { marker, capabilityNamespace })
		  Promise.resolve(NsecSigner.generate().signEvent(request))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRequestEvent/sign failed: #{json}")
		request = request_from(json)

		assert_equal "https://h/a.png", request.image
		assert_equal({ url: "https://h/a.png", m: "image/png", x: "abc", dim: "800x450" }, request.image_meta("https://h/a.png"))
	end

	test "the poster's escrow tier rides on the event and reads back through OpenRequest" do
		json = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE, Orders::Tiers::TIER2_ARBITER)
		  const [marker, capabilityNamespace, tier] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRequestEvent } = window.NostrCryptoTest
		  const data = { title: "T", capability: "c", budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "d", escrowTier: tier }
		  const { request } = buildRequestEvent(data, { marker, capabilityNamespace })
		  Promise.resolve(NsecSigner.generate().signEvent(request))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRequestEvent/sign failed: #{json}")

		assert_equal Orders::Tiers::TIER2_ARBITER, request_from(json).escrow_tier
	end

	test "a request with no escrow tier omits the tag and reads back as tier-1" do
		json = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRequestEvent } = window.NostrCryptoTest
		  const data = { title: "T", capability: "c", budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "d" }
		  const { request } = buildRequestEvent(data, { marker, capabilityNamespace })
		  Promise.resolve(NsecSigner.generate().signEvent(request))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRequestEvent/sign failed: #{json}")
		event = event_from(json)

		assert_not_includes event.tags.map(&:first), "escrow_tier"
		assert_equal Orders::Tiers::TIER1_HTLC, Requests::OpenRequest.new(event).escrow_tier
	end

	test "the budget carries no frequency and the request is never read as a service listing" do
		json = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, buildRequestEvent } = window.NostrCryptoTest
		  const data = { title: "T", capability: "c", budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "d" }
		  const { request } = buildRequestEvent(data, { marker, capabilityNamespace })
		  Promise.resolve(NsecSigner.generate().signEvent(request))
		    .then((s) => done(JSON.stringify(s))).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "buildRequestEvent/sign failed: #{json}")
		event = event_from(json)

		budget = event.tags.find { |t| t[0] == "price" }
		assert_equal 3, budget.size, "a bounty budget has no recurring frequency (price tag stays 3 elements)"
		assert_not_predicate Catalog::Listing.new(event), :conforms?, "a request lacks the service marker"
	end

	test "buildRequestEvent throws on a missing required field so a malformed request can never be signed" do
		result = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { buildRequestEvent } = window.NostrCryptoTest
		  const config = { marker, capabilityNamespace }
		  const full = { title: "T", capability: "c", budget: "1", deliveryWindow: "24h", claimWindow: "3d" }
		  const out = {}
		  const tryBuild = (key, patch) => {
		    try { buildRequestEvent({ ...full, ...patch }, config); out[key] = "NO THROW" }
		    catch (e) { out[key] = e.message }
		  }
		  for (const [key, patch] of [["title", { title: "" }], ["capability", { capability: "" }],
		    ["budget", { budget: "0" }], ["delivery", { deliveryWindow: "" }], ["claim", { claimWindow: "" }]]) tryBuild(key, patch)
		  done(JSON.stringify(out))
		JS
		out = JSON.parse(result)

		assert_match(/title/, out["title"])
		assert_match(/capability/, out["capability"])
		assert_match(/budget/, out["budget"])
		assert_match(/delivery/, out["delivery"])
		assert_match(/claim/, out["claim"])
	end

	private

	def event_from(json)
		e = JSON.parse(json)
		Event.new(kind: e["kind"], pubkey: e["pubkey"], content: e["content"], tags: e["tags"])
	end

	def request_from(json) = Requests::OpenRequest.new(event_from(json))
end

# Broadcast round-trips through a mock relay (signed by a generated key, no sign-in needed): the request
# publishes as a single kind-30402, with NO kind-31990 handler announcement (a demand posting is not a
# service handler).
class RequestPublishTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "broadcastRequest publishes only the kind-30402 request, never a handler announcement" do
		result = evaluate_async_script(<<~JS, Requests::OpenRequest.marker, Catalog::Listing::CAPABILITY_NAMESPACE)
		  const [marker, capabilityNamespace] = arguments
		  const done = arguments[arguments.length - 1]
		  const { NsecSigner, installMockRelays, broadcastRequest, RelaySet } = window.NostrCryptoTest
		  installMockRelays([{ url: "wss://pub.test" }])
		  const data = { title: "T", capability: "c", budget: "5000", deliveryWindow: "24h", claimWindow: "3d", dTag: "d1" }
		  broadcastRequest(data, { marker, capabilityNamespace }, NsecSigner.generate(), ["wss://pub.test"])
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
		assert_operator data["reached"], :>=, 1, "the request reached at least one relay"
		assert_match(/\A30402:.+:d1\z/, data["coordinate"], "the coordinate uses the supplied d-tag")
		assert_includes data["kinds"], 30_402, "the NIP-99 request landed on the relay"
		assert_not_includes data["kinds"], 31_990, "a request emits no handler announcement"
	end
end

# The full UI publish flow: fill the composer, sign with the held nsec key, and see the receipt.
class RequestComposerPublishTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "filling the composer and posting shows the success receipt" do
		sign_in_with_nsec
		click_link "Post a request" # Turbo-navigate from the home hero (preserves the injected crypto bridge)
		assert_text "Post an open request"

		execute_script(<<~JS)
		  window.NostrCryptoTest.installMockRelays([
		    { url: "wss://relay.damus.io" }, { url: "wss://relay.nostr.band" }, { url: "wss://nos.lol" }
		  ])
		JS

		fill_in "title", with: "Diagnose an engine"
		fill_in "capability", with: "diagnosis"
		fill_in "budget", with: "5000"
		fill_in "claim_value", with: "3"
		fill_in "delivery_value", with: "24"
		click_button "Sign & post request"

		assert_text "Request posted"
		assert_text "30402:" # the coordinate is shown on the receipt
	end

	test "choosing mediated escrow publishes a request carrying the tier-2 tag" do
		with_arbiter_key do
			sign_in_with_nsec
			click_link "Post a request" # Turbo nav -> the composer re-renders with the arbiter provisioned
			assert_text "Post an open request"

			execute_script(<<~JS)
			  window.NostrCryptoTest.installMockRelays([
			    { url: "wss://relay.damus.io" }, { url: "wss://relay.nostr.band" }, { url: "wss://nos.lol" }
			  ])
			JS

			fill_in "title", with: "Diagnose an engine"
			fill_in "capability", with: "diagnosis"
			fill_in "budget", with: "5000"
			fill_in "claim_value", with: "3"
			fill_in "delivery_value", with: "24"
			find("input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}']").click
			click_button "Sign & post request"
			assert_text "Request posted"

			assert_includes published_request_tags, [ "escrow_tier", Orders::Tiers::TIER2_ARBITER ]
		end
	end

	test "a mediated request above the tier-2 cap is blocked before signing" do
		with_arbiter_key do
			sign_in_with_nsec
			click_link "Post a request"
			assert_text "Post an open request"

			fill_in "title", with: "Big job"
			fill_in "capability", with: "diagnosis"
			fill_in "budget", with: (Orders::Policy.tier2_max_order_sats + 1).to_s
			fill_in "claim_value", with: "3"
			fill_in "delivery_value", with: "24"
			find("input[name='escrow_tier'][value='#{Orders::Tiers::TIER2_ARBITER}']").click
			click_button "Sign & post request"

			assert_text "Mediated escrow is limited to"
			assert_no_text "Request posted"
		end
	end

	private

	# The tags of the kind-30402 the composer just broadcast, read back from the per-context mock relay.
	def published_request_tags
		json = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { RelaySet } = window.NostrCryptoTest
		  const set = new RelaySet(["wss://relay.damus.io"])
		  let tags = []
		  new Promise((resolve) => {
		    set.subscribeMany([{ kinds: [30402] }], { onevent: (e) => { tags = e.tags }, oneose: resolve })
		    setTimeout(resolve, 800)
		  }).then(() => { set.close(); done(JSON.stringify(tags)) }).catch((e) => done("ERR:" + e.message))
		JS
		assert_no_match(/\AERR:/, json, "relay read failed: #{json}")
		JSON.parse(json)
	end

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_text "Provider studio"
	end
end
