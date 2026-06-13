# frozen_string_literal: true

module Orders
	# Lazily expire a single unfunded order the instant it is viewed past its funding deadline, so the state
	# flips immediately for the viewer instead of waiting on the background sweep (Escrow::ExpireSweepJob).
	# Routes through Orders::Transition (the sole state writer), so it is idempotent and concurrency-safe: it
	# no-ops unless the order is still awaiting funding past its deadline, and a funding that wins the race
	# leaves the order funded. Returns the order either way.
	class ExpireIfDue < BaseService
		option :order

		def call
			return order unless expirable?

			Orders::Transition.call(order:, to: Orders::States::EXPIRED, metadata: { "source" => "funding_deadline_lazy" })
		rescue IllegalTransitionError
			order # funded between the check and the transition; leave it funded
		end

		private

		def expirable?
			order.current_state == Orders::States::AWAITING_FUNDING &&
				order.funding_deadline_at.present? &&
				order.funding_deadline_at <= Time.current
		end
	end
end
