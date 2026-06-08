# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# End-to-end escrow lifecycle across the language boundary, against a real mint: the browser funds
# (mint -> HTLC lock), Rails records it (FUNDED), the provider verifies + redeems with the revealed
# preimage, and the Rails reconcile loop reads the mint and settles to RELEASED -- with no browser->Rails
# settlement call. Also drives the consumer refund path through order_settlement. Skips when no mint.
class OrderLifecycleTest < ApplicationSystemTestCase
	include CashuBridge

	FUND_JS = <<~JS
	  const [mint] = arguments
	  const done = arguments[arguments.length - 1]
	  const { Wallet, newKeypair, mintLockAndReport } = window.CashuEscrowTest
	  ;(async () => {
	  	const amount = 8
	  	const wallet = new Wallet(mint, { unit: "sat" })
	  	const provider = newKeypair(), refund = newKeypair()
	  	const locktime = Math.floor(Date.now() / 1000) + 3600
	  	const r = await mintLockAndReport({ wallet, mintUrl: mint, amount,
	  		providerPubkey: provider.pkHex, consumerRefundPubkey: refund.pkHex, locktime })
	  	done(JSON.stringify({ ok: true, amount, payload: r.payload, preimage: r.preimage, proofs: r.lockedProofs, providerSk: provider.skHex }))
	  })().catch((e) => done(JSON.stringify({ ok: false, error: String((e && e.message) || e) })))
	JS

	REDEEM_JS = <<~JS
	  const [mint, paramsJson] = arguments
	  const done = arguments[arguments.length - 1]
	  const { Wallet, verifyDeliveredProofs, redeemDelivered } = window.CashuEscrowTest
	  ;(async () => {
	  	const { proofs, preimage, providerSk, hashlock, lockPubkey, amount } = JSON.parse(paramsJson)
	  	const wallet = new Wallet(mint, { unit: "sat" })
	  	const check = await verifyDeliveredProofs({ wallet, proofs, hashlock, lockPubkey, amount })
	  	if (!check.ok) return done(JSON.stringify({ ok: true, verified: false, reason: check.reason }))
	  	const redeemed = await redeemDelivered({ wallet, proofs, preimage, providerPrivkey: providerSk })
	  	const total = redeemed.proofs.reduce((sum, p) => sum + Number(p.amount), 0)
	  	done(JSON.stringify({ ok: true, verified: true, redeemedTotal: total }))
	  })().catch((e) => done(JSON.stringify({ ok: false, error: String((e && e.message) || e) })))
	JS

	def setup
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason
		visit root_path
		load_cashu_bridge
		page.driver.browser.manage.timeouts.script_timeout = 60
	end

	test "release lifecycle: browser funds + provider redeems, Rails reconciles to RELEASED" do
		fund = JSON.parse(evaluate_async_script(FUND_JS, MINT_URL))
		assert fund["ok"], "fund failed: #{fund['error']}"
		payload = fund["payload"].deep_symbolize_keys
		order = build_order(amount_sats: fund["amount"])

		Orders::Funding.call(order:, **payload)
		assert_equal Orders::States::FUNDED, order.reload.current_state

		params = { proofs: fund["proofs"], preimage: fund["preimage"], providerSk: fund["providerSk"] }
		params.merge!(hashlock: payload[:hashlock], lockPubkey: payload[:lock_pubkey], amount: fund["amount"])
		redeem = JSON.parse(evaluate_async_script(REDEEM_JS, MINT_URL, params.to_json))
		assert redeem["ok"], "redeem failed: #{redeem['error']}"
		assert redeem["verified"], "provider rejected the delivered proofs: #{redeem['reason']}"
		assert_equal fund["amount"], redeem["redeemedTotal"], "provider redeemed the full amount"

		Orders::Reconcile.call(order:)
		assert_equal Orders::States::RELEASED, order.reload.current_state, "Rails reconciles the mint spend to RELEASED"
	end

	test "consumer refund reclaims a past-locktime lock through order_settlement" do
		result = run_scenario("settlementRefund")

		assert_equal 16, result["refundedTotal"], "the consumer reclaims the full budget"
		assert result["lockedSpent"], "the refunded proofs end SPENT at the mint"
	end
end
