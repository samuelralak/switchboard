# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Cross-language contract for the consumer funding flow (order_funding.js): the browser mints + locks the
# budget against a real mint, and the REAL Ruby Orders::Funding accepts the report it produces, so the JS
# output can never drift from the Rails escrow spine. Skips cleanly when no mint is up.
class OrderFundingTest < ApplicationSystemTestCase
	include CashuBridge

	def setup
		reason = mint_unavailable_reason
		skip("Cashu mint unavailable at #{MINT_URL}: #{reason}") if reason
		visit root_path
		load_cashu_bridge
		page.driver.browser.manage.timeouts.script_timeout = 60 # the flow does several mint round-trips
	end

	test "the browser funding report is accepted by Orders::Funding (real mint)" do
		result = run_scenario("fundReport")
		assert result["tokenOk"], "the lock produced a cashu token"
		assert result["preimageOk"], "the lock produced a 32-byte preimage"

		order = build_order(amount_sats: result["amount"])
		Orders::Funding.call(order:, **result["payload"].deep_symbolize_keys)

		assert_equal Orders::States::FUNDED, order.reload.current_state, "Rails accepts the browser-built report"
		assert_equal result["amount"], order.proofs.sum(:amount_sats), "the reported proofs fund the order amount"
	end
end
