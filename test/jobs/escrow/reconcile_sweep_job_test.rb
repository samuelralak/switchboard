# frozen_string_literal: true

require "test_helper"

module Escrow
	class ReconcileSweepJobTest < ActiveJob::TestCase
		test "enqueues a reconcile only for funded orders" do
			funded, = fund_order
			build_order # awaiting_funding, not swept

			assert_enqueued_with(job: Escrow::ReconcileJob, args: [ funded.id ]) do
				Escrow::ReconcileSweepJob.perform_now
			end
		end
	end
end
