# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Page-level E2E of the Tier-2 money path driven through the REAL order page + admin surface + Stimulus
# controllers. The dispute control plane (open -> rule -> claim affordance) is the Rails+Turbo half (no
# mint/relays). The funding round-trip drives the actual "Fund escrow" button end to end: the funding
# controller mints at the real mint, locks the 2-of-3, and reports it -- with the configured relays mocked
# (the global FakeWebSocket patch covers the page's own RelaySets). The on-mint co-sign/redeem crypto is
# additionally verified at the helper level (cashu_tier2_escrow_test).
class OrderTier2PageTest < ApplicationSystemTestCase
	include CashuBridge

	PASSPHRASE = "correct horse battery staple"

	def setup
		visit root_path
		load_nostr_bridge
	end

	test "a funded tier-2 order page mounts the settlement controller and the dispute affordance for the consumer" do
		me = new_identity
		order = funded_tier2(consumer: me[:pubkey])

		sign_in(me[:nsec])
		visit order_path(order)

		assert_selector "[data-controller~='settlement'][data-settlement-tier-value='#{Orders::Tiers::TIER2_ARBITER}']"
		assert_selector "[data-settlement-target='release']" # the consumer release control is wired
		assert_text "Open a dispute"
	end

	test "an awaiting-funding tier-2 order page mounts the funding controller with the tier + platform arbiter" do
		me = new_identity
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000,
			consumer_pubkey: me[:pubkey], provider_pubkey: SecureRandom.hex(32))

		with_arbiter_key do
			sign_in(me[:nsec])
			visit order_path(order)

			assert_selector "[data-controller~='funding'][data-funding-tier-value='#{Orders::Tiers::TIER2_ARBITER}']"
			assert_selector "[data-funding-arbiter-value='#{platform_arbiter_pubkey}']"
			assert_text "Fund escrow"
		end
	end

	test "the consumer funds a tier-2 order end to end from the Fund button (real mint)" do
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason

		# set for the whole test: both the render (the arbiter data value) and the later funding POST validation
		ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = TEST_ARBITER_PRIVKEY
		consumer = new_identity
		provider = new_identity
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 4,
			consumer_pubkey: consumer[:pubkey], provider_pubkey: provider[:pubkey], mint_url: MINT_URL)

		fund_tier2_on_page(order, consumer, provider)

		order.reload
		assert_equal Orders::States::FUNDED, order.current_state
		assert_nil order.lock.hashlock, "a tier-2 lock carries no hashlock"
		assert_equal platform_arbiter_pubkey, order.lock.arbiter_pubkey, "locked to the platform arbiter"
		assert_equal 2, order.lock.required_signatures
	ensure
		ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY")
	end

	test "the ruled-for consumer claims with the arbiter co-signature end to end (real mint + arbiter endpoint)" do
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason

		ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = TEST_ARBITER_PRIVKEY
		saved_origin = Rails.application.config.x.canonical_origin
		# the NIP-98 u-tag AND the arbiter POST target both derive from canonical_origin; point it at the test
		# server, then re-render so the sign-in + arbiter URLs are built against it (else their u-tags mismatch).
		Rails.application.config.x.canonical_origin = page.server.base_url
		visit root_path
		consumer = new_identity
		provider = new_identity
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 4,
			consumer_pubkey: consumer[:pubkey], provider_pubkey: provider[:pubkey], mint_url: MINT_URL)

		# funds for real; the consumer keeps the local backup + cached escrow key on the device
		fund_tier2_on_page(order, consumer, provider)
		order.reload # the browser funded it; refresh the stale in-memory state before transitioning it

		# the consumer disputes; the operator rules it their way; the consumer now claims with the arbiter co-sign
		Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey, reason: "no delivery")
		Orders::RuleDispute.call(order:, winner: "consumer")

		visit order_path(order) # re-render: disputed + ruled_for_consumer -> the winning consumer sees the claim
		assert_text "Claim with arbiter co-signature"
		click_button "Claim with arbiter co-signature"
		unlock_signer # the hard reload cleared the in-memory signer

		# doDisputeRedeem: co-sign with the ESCROW key, fetch the arbiter sig over NIP-98 with the LOGIN key,
		# redeem the 2-of-3 at the real mint, then settle. The settle broadcast repaints the page to the
		# terminal state (ruled_for_consumer -> the funds return -> REFUNDED).
		assert_text "Refunded to you", wait: 40
		assert_equal Orders::States::REFUNDED, order.reload.current_state
	ensure
		Rails.application.config.x.canonical_origin = saved_origin
		ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY")
	end

	test "the happy-path tier-2 co-sign release+redeem settles to RELEASED (real mint)" do
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason

		ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = TEST_ARBITER_PRIVKEY
		consumer = new_identity
		provider = new_identity
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 4,
			consumer_pubkey: consumer[:pubkey], provider_pubkey: provider[:pubkey], mint_url: MINT_URL)

		fund_tier2_on_page(order, consumer, provider) # the consumer funds for real; the cosign relays stay installed

		# the consumer RELEASES on the page: doReleaseTier2 co-signs the locked proofs with the escrow key and
		# ships them to the provider over the 'cosign' NIP-17 message, then records the release.
		click_button "Release escrow"
		40.times { break if order.reload.release.present?; sleep 0.5 } # the record POST follows the cosign send
		assert order.release.present?, "the consumer's release is recorded"

		# the PROVIDER half: no second browser session is possible (mock relays are per-context), so drive the
		# same operations doRedeemTier2 runs -- read the cosign, add the provider escrow co-signature, redeem.
		redeem = provider_redeem_cosign(order, consumer, provider)
		assert redeem["spent"], "the provider's co-signature completed the 2-of-3 spend: #{redeem['error']}"

		Orders::Reconcile.call(order:) # Rails observes the spend at the mint
		assert_equal Orders::States::RELEASED, order.reload.current_state # 2-sig, no ruling -> released
	ensure
		ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY")
	end

	test "the consumer opens a dispute from the order page and the page reflects it" do
		me = new_identity
		order = funded_tier2(consumer: me[:pubkey])

		sign_in(me[:nsec])
		visit order_path(order)
		find("textarea[name='dispute[reason]']").set("the work was never delivered")
		accept_confirm { click_button "Open a dispute" }

		assert_text "In dispute" # the lifecycle chip repaints on the redirect
		assert_equal Orders::States::DISPUTED, order.reload.current_state
		assert_equal "the work was never delivered", order.dispute.reason
	end

	test "the consumer's tier-2 Refund is blocked before the locktime (doRefund guard surfaces an error)" do
		me = new_identity
		order = funded_tier2(consumer: me[:pubkey]) # locktime is days out

		sign_in(me[:nsec])
		visit order_path(order)
		click_button "Refund" # doRefund's guard throws before touching the signer/mint

		assert_text "Refund is available after the lock expires"
		assert_equal Orders::States::FUNDED, order.reload.current_state # nothing spent or settled
	end

	test "the provider's tier-2 Verify surfaces an error when no budget was delivered (doVerifyTier2)" do
		me = new_identity
		order = funded_tier2(provider: me[:pubkey])

		sign_in(me[:nsec])
		visit order_path(order)
		load_nostr_bridge
		install_mock_relays # so the delivery fetch returns nothing fast instead of hitting real relays

		click_button "Verify funds"
		unlock_signer # the relay fetch needs the signer; the fresh page must unlock it first

		# doVerifyTier2 -> fetchDelivery finds no token-delivery -> the controller surfaces the error
		assert_text "The consumer has not delivered the locked budget yet"
	end

	test "the provider's funded tier-2 order page carries the arbiter pubkey + verify/redeem and a dispute affordance" do
		me = new_identity
		order = funded_tier2(provider: me[:pubkey])

		sign_in(me[:nsec])
		visit order_path(order)

		assert_selector "[data-settlement-arbiter-pubkey-value='#{order.lock.arbiter_pubkey}']"
		assert_selector "[data-settlement-locktime-value='#{order.lock.locktime.to_i}']" # the anti refund-steal binding
		assert_text "Verify funds"
		assert_text "Open a dispute"
	end

	test "an operator rules an open dispute from the admin surface" do
		operator = new_identity
		with_operator(operator[:pubkey]) do
			order = funded_tier2(consumer: SecureRandom.hex(32), provider: SecureRandom.hex(32))
			Orders::OpenDispute.call(order:, opened_by_pubkey: order.consumer_pubkey, reason: "stalled")

			sign_in(operator[:nsec])
			visit admin_disputes_path
			assert_text order.listing_coordinate

			accept_confirm { click_button "Rule for provider" }

			assert_no_text order.listing_coordinate # the ruled dispute leaves the open queue (waits for the POST)
			assert order.dispute.reload.ruled_for_provider?
		end
	end

	test "the winning provider's page offers the arbiter-cosigned claim on a ruled dispute" do
		me = new_identity
		order = funded_tier2(provider: me[:pubkey])
		Orders::Transition.call(order:, to: Orders::States::DISPUTED)
		order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status: Orders::DisputeStatuses::RULED_FOR_PROVIDER)

		sign_in(me[:nsec])
		visit order_path(order)

		assert_text "Claim with arbiter co-signature"
		assert_selector "[data-settlement-target='disputeRedeem']"
		# the arbiter endpoint URL is rendered absolute (canonical origin) so the NIP-98 u-tag verifies
		assert_selector "[data-settlement-arbiter-url-value*='/api/orders/#{order.id}/arbiter_signatures']"
	end

	private

	def new_identity
		keypair = Nostr::Keygen.new.generate_key_pair
		{ pubkey: keypair.public_key.to_s, privkey: keypair.private_key.to_s,
			nsec: Nostr::Bech32.nsec_encode(keypair.private_key.to_s) }
	end

	# Drive the real "Fund escrow" button to FUNDED: sign in, mock the relays + seed the provider escrow, click
	# Fund, unlock the saved key, and wait for the funded consumer action. Leaves the consumer's backup + cached
	# escrow key on the device (so a later same-session dispute claim is relay-free).
	def fund_tier2_on_page(order, consumer, provider)
		sign_in(consumer[:nsec])
		visit order_path(order)
		load_nostr_bridge # the order page is a fresh load; re-inject the test bridge to seed relays/escrow
		page.driver.browser.manage.timeouts.script_timeout = 30
		install_relays_and_publish_provider_escrow(provider, MINT_URL)

		click_button "Fund escrow"
		unlock_signer # the hard page load cleared the in-memory signer; the funding controller prompts to unlock
		assert_text "Release escrow", wait: 40 # the funded consumer action appears once the report lands
	end

	def unlock_signer
		within "#signer-unlock-dialog" do
			find('[data-signer-unlock-target="passphrase"]').set(PASSPHRASE)
			click_button "Unlock"
		end
	end

	# The provider half of the happy-path redeem, run in the consumer's still-loaded browser session (a second
	# Capybara session would get its own mock-relay context). Mirrors settlement_controller#doRedeemTier2: read
	# the consumer's 'cosign' message, add the provider escrow co-signature, and redeem the 2-of-3 at the mint.
	def provider_redeem_cosign(order, consumer, provider)
		JSON.parse(evaluate_async_script(PROVIDER_REDEEM_JS, provider[:privkey], provider[:pubkey],
			consumer[:pubkey], MINT_URL, order.id, NostrClient.configuration.relays))
	end

	PROVIDER_REDEEM_JS = <<~JS
	  const [provPriv, provPub, consPub, mint, orderId, relays] = arguments
	  const done = arguments[arguments.length - 1]
	  const { NsecSigner, escrowMessages, escrowIdentity } = window.NostrCryptoTest
	  ;(async () => {
	  	const signer = NsecSigner.fromHex(provPriv)
	  	const me = await escrowIdentity.ensureEscrowIdentity({ accountPubkey: provPub, signer, relays, mints: [mint] })
	  	const cosign = await escrowMessages.latestEscrowMessage({ signer, ownPubkey: provPub, relays, orderId, type: "cosign", from: consPub })
	  	if (!cosign?.data?.proofs?.length) return done(JSON.stringify({ spent: false, error: "no cosign message reached the provider" }))
	  	const { partySign, redeemTier2 } = await import("nostr/order_settlement")
	  	const { proofState } = await import("nostr/cashu_escrow")
	  	const { Wallet } = await import("@cashu/cashu-ts")
	  	const wallet = new Wallet(mint, { unit: "sat" })
	  	await redeemTier2({ wallet, signedProofs: partySign({ proofs: cosign.data.proofs, privkey: me.privkeyHex }) })
	  	const after = await proofState({ wallet, proofs: cosign.data.proofs })
	  	done(JSON.stringify({ spent: after.every((s) => s.state === "SPENT") }))
	  })().catch((e) => done(JSON.stringify({ spent: false, error: String((e && e.message) || e) })))
	JS

	# Mock the configured relays (the global FakeWebSocket patch covers the page controllers' own RelaySets) so
	# a relay fetch resolves offline (empty) instead of reaching real relays.
	def install_mock_relays
		evaluate_async_script(<<~JS, NostrClient.configuration.relays)
		  const [relays] = arguments
		  const done = arguments[arguments.length - 1]
		  window.NostrCryptoTest.installMockRelays(relays.map((url) => ({ url, authRequired: false })))
		  done(true)
		JS
	end

	# Mock the configured relays (the global FakeWebSocket patch covers the page controllers' own RelaySets)
	# and publish the PROVIDER's NIP-61 escrow advertisement so the consumer's funding flow discovers it.
	def install_relays_and_publish_provider_escrow(provider, mint_url)
		relays = NostrClient.configuration.relays
		raw = evaluate_async_script(<<~JS, relays, provider[:privkey], provider[:pubkey], mint_url)
		  const [relays, providerPriv, providerPub, mintUrl] = arguments
		  const done = arguments[arguments.length - 1]
		  const { installMockRelays, NsecSigner, escrowIdentity } = window.NostrCryptoTest
		  installMockRelays(relays.map((url) => ({ url, authRequired: false })))
		  escrowIdentity.ensureEscrowIdentity({ accountPubkey: providerPub, signer: NsecSigner.fromHex(providerPriv), relays, mints: [mintUrl] })
		    .then((me) => done(JSON.stringify({ ok: true, escrowPub: me.pubkeyHex })))
		    .catch((e) => done(JSON.stringify({ ok: false, error: String((e && e.message) || e) })))
		JS
		parsed = JSON.parse(raw)
		flunk("provider escrow publish failed: #{parsed['error']}") unless parsed["ok"]
	end

	def funded_tier2(consumer: SecureRandom.hex(32), provider: SecureRandom.hex(32))
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000,
			consumer_pubkey: consumer, provider_pubkey: provider)
		fund_tier2_order(order)
	end

	def with_operator(pubkey)
		saved = Rails.application.config.x.operator_pubkeys
		Rails.application.config.x.operator_pubkeys = [ pubkey ]
		yield
	ensure
		Rails.application.config.x.operator_pubkeys = saved
	end

	def sign_in(nsec)
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_text "Provider studio"
	end
end
