# frozen_string_literal: true

module Escrow
	# Operator signal for escrow that has gone quiet: an order still SETTLEABLE (funded/disputed) well past its
	# locktime has been neither redeemed nor refunded -- usually a dead or unresponsive mint (the reconcile
	# sweep retries forever but can never recover a vanished mint, and never escalates), or stranded parties.
	# Logs a warning the monitoring vendor escalates; it never mutates an order. Returns the stuck orders.
	class StuckAlert < BaseService
		def call
			stuck = stuck_orders
			return stuck if stuck.empty?

			ids = stuck.first(20).map(&:id).join(", ")
			Rails.logger.warn("[Escrow::StuckAlert] #{stuck.size} order(s) past locktime+grace (dead mint?): #{ids}")
			stuck
		end

		private

		# Settleable orders whose locktime passed more than the grace window ago (neither redeemed nor refunded).
		def stuck_orders
			cutoff = Rails.application.config.x.escrow.stuck_grace_seconds.seconds.ago
			Order.in_state(*Orders::States::SETTLEABLE).joins(:lock).where(order_locks: { locktime: ..cutoff }).to_a
		end
	end
end
