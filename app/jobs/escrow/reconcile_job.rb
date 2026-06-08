# frozen_string_literal: true

module Escrow
	# Reconcile one funded order against the mint. A transient mint outage retries with backoff, then defers to
	# the next sweep; a stale transition is discarded by ApplicationJob.
	class ReconcileJob < ApplicationJob
		queue_as :escrow

		# At most one reconcile per order in flight; a duplicate sweep enqueue is dropped (the next sweep re-checks).
		limits_concurrency to: 1, key: ->(order_id) { order_id }, on_conflict: :discard

		retry_on Cashu::MintError, wait: :polynomially_longer, attempts: 5 do |job, error|
			Rails.logger.warn("[#{job.class.name}] mint unavailable, deferring to the next sweep: #{error.message}")
		end
		retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

		def perform(order_id)
			order = Order.find_by(id: order_id)
			Orders::Reconcile.call(order:) if order
		end
	end
end
