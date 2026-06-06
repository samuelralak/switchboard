# frozen_string_literal: true

require "test_helper"

module Pricing
	class BtcRateTest < ActiveSupport::TestCase
		test "parses the Coinbase spot shape into a float" do
			rate = BtcRate.new.send(:parse, '{"data":{"amount":"95000.50","base":"BTC","currency":"USD"}}')

			assert_in_delta 95_000.50, rate, 0.001
		end

		test "returns nil for a malformed or empty payload, never raising" do
			assert_nil BtcRate.new.send(:parse, "not json")
			assert_nil BtcRate.new.send(:parse, '{"data":{}}')
			assert_nil BtcRate.new.send(:parse, '{"data":{"amount":"abc"}}')
		end

		test "call makes no external request in the test environment" do
			assert_nil BtcRate.call # the test guard keeps the suite hermetic
		end
	end
end
