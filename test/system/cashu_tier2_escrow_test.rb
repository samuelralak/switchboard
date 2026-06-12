# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Merge gate for the Tier-2 arbiter escrow primitive (2-of-3 P2PK, NO hashlock): drives the lock + the four
# spend paths (happy, dispute-for-provider, dispute-for-consumer, timeout refund) and the negatives in the
# browser against a local nutshell FakeWallet mint via the scenarios in cashu_test_support.js. This is the
# slice-2 gate from docs/tier2-arbiter-escrow.md: no Rails Tier-2 settlement code ships until this is green.
# No Rails/NIP-17/UI here, just the crypto primitive. Skips cleanly when no mint is up.
class CashuTier2EscrowTest < ApplicationSystemTestCase
	include CashuBridge

	def setup
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason

		visit root_path
		load_cashu_bridge
		page.driver.browser.manage.timeouts.script_timeout = 60 # the flow does several mint round-trips
	end

	test "builds a real 2-of-3 secret and releases on the happy path with two signatures" do
		r = run_scenario("tier2LockAndHappyRelease")
		assert_equal "P2PK", r["kind"], "Tier-2 must be a pure P2PK secret (no HTLC/hashlock)"
		assert r["dataNonEmpty"], "the secret data field must hold a pubkey (a signer), not be empty"
		assert r["signerSetMatches"], "the 2-of-3 signer set must be exactly {consumer, provider, arbiter}"
		assert_equal "2", r["nSigs"], "n_sigs must be 2 (a 2-of-3)"
		assert r["hasRefund"], "a refund pathway (consumer alone after locktime) must be present"
		assert r["beforeUnspent"], "the locked proofs must be UNSPENT before release"
		assert_equal 64, r["redeemedTotal"], "the happy-path release must move the full amount (fees off)"
		assert r["spent"], "the locked proofs must read SPENT after release"
		assert_operator r["witnessSigCount"], :>=, 2, "the release witness must carry the two signatures"
	end

	test "an arbiter-and-provider quorum releases the funds (dispute for the provider)" do
		r = run_scenario("tier2DisputeForProvider")
		assert_equal 32, r["redeemedTotal"], "arbiter+provider (2-of-3) must release the full amount"
		assert r["spent"], "the locked proofs must read SPENT"
	end

	test "an arbiter-and-consumer quorum returns the funds (dispute for the consumer)" do
		r = run_scenario("tier2DisputeForConsumer")
		assert_equal 32, r["redeemedTotal"], "arbiter+consumer (2-of-3) must return the full amount"
		assert r["spent"], "the locked proofs must read SPENT"
	end

	test "after the locktime the consumer refunds alone with a single signature" do
		r = run_scenario("tier2TimeoutRefund")
		assert_equal 16, r["refundedTotal"], "the consumer must reclaim the full amount after locktime"
		assert r["spent"], "the refund must consume the locked proofs"
		assert_equal 1, r["witnessSigCount"], "the refund pathway takes exactly one signature (no arbiter)"
	end

	test "a single signature cannot release a 2-of-3 lock" do
		r = run_scenario("tier2SingleSigRejected")
		assert r["threw"], "redeeming with one of the two required signatures must be rejected"
		assert r["stillUnspent"], "a rejected release must not spend the locked proofs"
	end

	test "the consumer cannot refund before the locktime" do
		r = run_scenario("tier2RefundBeforeLocktimeRejected")
		assert r["threw"], "a refund before the locktime must be rejected"
		assert r["stillUnspent"], "a rejected refund must not spend the locked proofs"
	end

	test "the Ruby arbiter pubkey derivation matches cashu-ts for the same key" do
		r = run_scenario("arbiterPubkeyDerivation")
		assert_equal r["pubkey"], Escrow::ArbiterSigner.new(private_key: "11" * 32).pubkey,
			"the platform arbiter pubkey must be identical across Ruby (ecdsa_ext) and the browser (cashu-ts)"
	end

	test "the browser tier-2 funding report is accepted by Orders::Funding (real mint)" do
		result = run_scenario("tier2FundReport")
		assert result["tokenOk"], "the lock produced a cashu token"

		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: result["amount"])
		with_arbiter_key { Orders::Funding.call(order:, **result["payload"].deep_symbolize_keys) }

		assert_equal Orders::States::FUNDED, order.reload.current_state, "Rails accepts the browser-built tier-2 report"
		assert_nil order.lock.hashlock, "a tier-2 lock carries no hashlock"
		assert_equal result["arbiterPubkey"], order.lock.arbiter_pubkey, "the platform arbiter is recorded"
		assert_equal 2, order.lock.required_signatures
	end

	# Slice-4 merge gate: a Ruby-produced (server-side) arbiter signature completes a 2-of-3 spend at the real
	# mint. The browser builds the lock + provider-signs; Ruby's Escrow::ArbiterSigner signs the secrets; the
	# browser appends them and redeems. If the mint SPENDS the proofs, server-side arbiter signing is viable.
	test "a Ruby-produced arbiter signature completes a 2-of-3 spend at the mint" do
		build = run_scenario("tier2ServerSignBuild")
		arbiter = Escrow::ArbiterSigner.new(private_key: "33" * 32)
		arbiter_sigs = build["secrets"].map { |secret| arbiter.sign(secret) }

		result = run_scenario_args("tier2ServerSignRedeem", { proofs: build["proofs"], arbiterSigs: arbiter_sigs })

		assert result["spent"], "the mint must accept the Ruby arbiter signature in the 2-of-3 witness"
		assert_equal 32, result["redeemedTotal"], "the full amount must move (fees off)"
	end

	# Slice B7: the order_settlement.js settlement layer (the code the order page actually runs) verifies a
	# tier-2 lock and completes the happy-path co-sign redeem at the real mint.
	test "the order_settlement helpers verify a tier-2 lock and complete the happy-path redeem" do
		r = run_scenario("tier2SettlementHelpers")

		assert r["verifyOk"], "verifyTier2Lock accepts a genuine 2-of-3 locked to the provider + arbiter"
		assert r["wrongAmountRejected"], "verifyTier2Lock rejects a wrong amount"
		assert r["strangerRejected"], "verifyTier2Lock rejects a lock that does not carry the caller's key"
		assert r["wrongLocktimeRejected"], "verifyTier2Lock rejects an on-mint locktime != the recorded one"
		assert_equal 32, r["redeemedTotal"], "consumer + provider co-sign releases the full amount"
		assert r["spent"], "the locked proofs read SPENT after the helper redeem"
	end

	# Slice B7: the winning party's dispute redeem, end to end through order_settlement -- the provider
	# co-signs (partySign), Ruby's arbiter signs, applyArbiterSignatures merges to the 2-of-3, redeemTier2 spends.
	test "a Ruby arbiter signature merged via applyArbiterSignatures completes the dispute redeem" do
		build = run_scenario("tier2DisputeRedeemBuild")
		arbiter = Escrow::ArbiterSigner.new(private_key: "33" * 32)
		arbiter_sigs = build["secrets"].map { |secret| arbiter.sign(secret) }

		result = run_scenario_args("tier2DisputeRedeemApply", { proofs: build["proofs"], arbiterSigs: arbiter_sigs })

		assert result["spent"], "applyArbiterSignatures + redeemTier2 complete the provider + arbiter 2-of-3"
		assert_equal 32, result["redeemedTotal"], "the full amount must move (fees off)"
	end

	# Crash-safety (review finding): funding writes a local recovery marker the instant funds lock, before the
	# report round-trip, so a crash there cannot orphan the lock (the resume guard keys on the token, never re-mints).
	test "tier-2 funding persists a crash-safe local marker before the report, and it re-derives the report" do
		r = run_scenario("tier2FundingCrashMarker")

		assert r["markerHasToken"], "the marker holds the spendable token the instant funds lock"
		assert r["markerHasProofs"], "the marker holds the locked proofs"
		assert r["markerHasNoPayload"], "the crash marker precedes the full (with-payload) backup"
		assert r["markerHasArbiterField"], "the marker carries the lock fields needed to re-report"
		assert r["reReportMatches"], "reportFromSaved re-derives the same report Ys from the marker"
	end

	# Slice B7: the NIP-98 client (nip98.js) the dispute redeem uses to authenticate the arbiter-signatures call
	# emits a header the server's real verifier (Events::VerifyHttpAuth: canonical id + BIP-340 sig + tags) accepts.
	test "nip98.js builds an Authorization header the server NIP-98 verifier accepts" do
		privkey = "44" * 32
		url = "#{Rails.application.config.x.canonical_origin}/api/orders/#{SecureRandom.uuid}/arbiter_signatures"
		body = %q({"secrets":["abc"]})

		built = run_scenario_args("buildNip98Header", { privkey:, url:, method: "POST", body: })
		event = JSON.parse(Base64.strict_decode64(built["header"].split(" ", 2).last))

		verified = Events::VerifyHttpAuth.call(event_data: event, http_method: "POST", url:, body:)
		assert_equal Events::Kinds::HTTP_AUTH, verified["kind"]
		assert_equal built["pubkey"], event["pubkey"], "the header is signed by the caller's login key"
	end
end
