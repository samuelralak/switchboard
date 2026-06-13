# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Merge gate for the non-custodial Cashu HTLC escrow primitive (Tier 1): drives the lock -> release -> refund
# flow (and its negatives) in the browser against a local nutshell FakeWallet mint via the scenarios in
# cashu_test_support.js. No Rails/NIP-17/UI here, just the crypto primitive. Skips cleanly when no mint is up
# so the suite stays green; run it where the mint is reachable to exercise the money path.
class CashuEscrowTest < ApplicationSystemTestCase
	include CashuBridge

	def setup
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason
		visit root_path
		load_cashu_bridge
		page.driver.browser.manage.timeouts.script_timeout = 60 # the flow does several mint round-trips
	end

	test "locks an HTLC, blocks redeem without the preimage, releases with it, and reveals it via NUT-07" do
		r = run_scenario("lockReleaseReveal")
		assert r["tokenOk"], "lock did not return a cashu token"
		assert r["preimageOk"], "preimage is not 64 hex"
		assert r["beforeUnspent"], "locked proofs should be UNSPENT before redeem"
		assert r["negThrew"], "redeem with a wrong preimage must be rejected"
		assert r["stillUnspentAfterNeg"], "a failed redeem must not spend the proofs"
		assert_equal 64, r["redeemedTotal"], "provider should receive the full locked amount (fees off)"
		assert_equal r["expectedPreimage"], r["revealedPreimage"], "the SPENT witness must reveal the preimage"
	end

	test "refunds to the consumer with a signature only after the locktime has passed" do
		r = run_scenario("refundAfterLocktime")
		assert_equal 32, r["refundedTotal"], "consumer should reclaim the full amount after locktime"
		assert r["lockedSpent"], "the refund must consume the locked proofs"
	end

	test "after a redeem the proofs read spent, so a second redeem must not resubmit them" do
		r = run_scenario("doubleRedeemIsIdempotent")
		assert r["allSpent"], "the locked proofs must read SPENT after a redeem (the re-redeem guard's check)"
		assert r["reSwapThrew"], "a naive second redeem is rejected by the mint (proofs already spent)"
	end

	test "rejects a refund attempted before the locktime" do
		r = run_scenario("refundBeforeLocktime")
		assert r["threw"], "a refund before the locktime must be rejected"
		assert r["stillUnspent"], "a rejected refund must not spend the locked proofs"
	end

	test "a funding resume refuses to re-lock proofs a prior attempt already spent" do
		r = run_scenario("fundingResumeRejectsSpentProofs")
		assert r["threw"], "resuming onto already-spent minted proofs must fail, not silently retry the swap"
		assert r["rejectedAsSpent"], "the failure must be the honest cannot-be-re-locked guard, not an opaque mint error"
	end

	test "the top-up solver always covers a fee-charging mint's swap fee" do
		r = run_scenario("topUpMath")
		assert r["covered"], "minting have + top-up must cover amount plus the real swap fee, for every case"
		assert_operator r["stuckTopup"], :>=, 2, "a 10-proof stuck recovery needs >= 2 extra sat (the production bug was 1)"
		assert_equal 0, r["freeExisting"], "a free mint already covered needs no top-up"
	end

	test "funding tops up an under-minted attempt and locks the full amount" do
		r = run_scenario("fundingTopsUpAShortfall")
		assert_equal r["amount"], r["lockedTotal"], "the top-up must recover the partial mint and lock the full amount"
		assert r["tokenOk"], "the recovered lock must produce a cashu token"
	end
end
