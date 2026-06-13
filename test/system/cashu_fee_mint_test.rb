# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Funding against a FEE-CHARGING mint (NUT-02 input_fee_ppk > 0): exercises the lock-swap fee math and the
# top-up recovery, which the default 0-fee local mint cannot. Point CASHU_MINT_URL at a fee mint (a second
# nutshell with MINT_INPUT_FEE_PPK set); skips cleanly when the mint is absent or charges no fee.
class CashuFeeMintTest < ApplicationSystemTestCase
	include CashuBridge

	def setup
		reason = mint_unavailable_reason
		skip("fee mint unavailable at #{MINT_URL}: #{reason}") if reason
		skip("#{MINT_URL} charges no input fee; set CASHU_MINT_URL to a fee mint") unless fee_mint?
		visit root_path
		load_cashu_bridge
		page.driver.browser.manage.timeouts.script_timeout = 60
	end

	test "a fresh order funds fully on a fee-charging mint" do
		r = run_scenario("feeFreshFund")
		assert_equal r["amount"], r["lockedTotal"], "the full order amount must lock; the fee is minted on top"
		assert r["tokenOk"], "the lock must produce a cashu token"
	end

	test "an under-minted order recovers and locks the full amount on a fee mint" do
		r = run_scenario("fundingFeeStuckRecovery")
		assert_equal r["amount"], r["lockedTotal"], "the top-up must cover the real swap fee for the combined proof set"
		assert r["tokenOk"], "the recovered lock must produce a cashu token"
	end

	private

	# True when the configured mint advertises a positive input fee on its active sat keyset.
	def fee_mint?
		require "net/http"
		body = Net::HTTP.get(URI("#{MINT_URL}/v1/keysets"))
		JSON.parse(body)["keysets"].any? { |k| k["active"] && k["unit"] == "sat" && k["input_fee_ppk"].to_i.positive? }
	rescue StandardError
		false
	end
end
