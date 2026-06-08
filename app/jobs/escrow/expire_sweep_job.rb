# frozen_string_literal: true

module Escrow
	# Expire unfunded orders past their funding deadline. This recurring sweep is the authoritative, crash-safe
	# timer (it re-scans each run). A concurrent funding wins the race and the order is left funded.
	class ExpireSweepJob < ApplicationJob
		queue_as :escrow

		def perform
			Order.funding_due.find_each do |order|
				Orders::Transition.call(order:, to: Orders::States::EXPIRED, metadata: { "source" => "funding_deadline" })
			rescue IllegalTransitionError
				next # the order funded between the scan and the transition; leave it
			rescue StandardError => e
				Rails.logger.error("[#{self.class.name}] expire failed for order #{order.id}: #{e.class}: #{e.message}")
				next # isolate; the next sweep retries this order
			end
		end
	end
end
