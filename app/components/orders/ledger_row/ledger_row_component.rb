# frozen_string_literal: true

module Orders
	module LedgerRow
		# One row in the consumer's order ledger (Orders::Ledger::Row): the service, the escrow state chip, the
		# amount, and, while awaiting funding, how long the funding window has left. The whole row links to the
		# order page. The chip shares OrdersHelper.status_presentation with the order-page status strip.
		class LedgerRowComponent < ApplicationComponent
			attr_reader :row

			def initialize(row:)
				@row = row
			end

			def status = @status ||= helpers.status_presentation(row.state, delivered: row.delivered)
			# Opens the order drawer via the URL (?order_id); refresh keeps it open, the backdrop/Esc close it.
			def order_path = helpers.requests_path(order_id: row.id)
			def awaiting? = row.state == Orders::States::AWAITING_FUNDING
			def funding_left = helpers.distance_of_time_in_words(Time.current, row.funding_deadline_at)
		end
	end
end
