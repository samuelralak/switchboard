# frozen_string_literal: true

require "test_helper"

module Escrow
	class StuckAlertTest < ActiveSupport::TestCase
		test "flags a settleable order whose locktime is past the grace window, not a current one" do
			stuck, = fund_order
			stuck.lock.update!(locktime: 2.days.ago) # simulate the locktime long passed, order still funded
			fresh, = fund_order

			flagged = Escrow::StuckAlert.call.map(&:id)

			assert_includes flagged, stuck.id
			assert_not_includes flagged, fresh.id
		end

		test "returns empty (and stays silent) when nothing is past the grace" do
			fund_order # locktime 1.hour.from_now by default

			assert_empty Escrow::StuckAlert.call
		end
	end
end
