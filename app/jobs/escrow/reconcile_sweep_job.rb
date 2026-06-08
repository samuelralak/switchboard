# frozen_string_literal: true

module Escrow
	# Enqueue a per-order reconcile for every funded order. Crash-safe: each run re-scans, so a missed tick or a
	# dropped job is recovered on the next sweep (no outbox needed).
	class ReconcileSweepJob < ApplicationJob
		queue_as :escrow

		def perform
			Order.in_state(Orders::States::FUNDED).find_each do |order|
				ReconcileJob.perform_later(order.id)
			rescue StandardError => e
				Rails.logger.error("[#{self.class.name}] enqueue failed for order #{order.id}: #{e.class}: #{e.message}")
				next # isolate; the next sweep re-scans this order
			end
		end
	end
end
