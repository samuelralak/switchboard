# frozen_string_literal: true

require "application_system_test_case"
require_relative "support/cashu_bridge"

# Smoke: confirms @cashu/cashu-ts v4.5.1 loads in the browser under the import map + CSP (the +esm vendoring
# caveat makes this a real unknown) and exposes the API the escrow module builds on. Mint-independent, so it
# runs everywhere the full escrow test skips.
class CashuEscrowSmokeTest < ApplicationSystemTestCase
	include CashuBridge

	test "cashu-ts loads in the browser and exposes its API" do
		visit root_path
		load_cashu_bridge("CashuTest")

		exports = evaluate_script("window.CashuTest && window.CashuTest.exports")
		assert exports.present?, "cashu-ts did not load; in-page error: #{evaluate_script('window.__cashuErr')}"
		%w[getEncodedToken getDecodedToken].each do |name|
			assert_includes exports, name, "expected cashu-ts to export #{name}"
		end
	end
end
