# frozen_string_literal: true

module Orders
	module LedgerRow
		# One row in the consumer's order ledger (Orders::Ledger::Row): the service, the escrow state chip, the
		# amount, and, while awaiting funding, how long the funding window has left. The whole row links to the
		# order page. The chip shares OrdersHelper.status_presentation with the order-page status strip.
		class LedgerRowComponent < ApplicationComponent
			attr_reader :row

			def initialize(row:, selected: false)
				@row = row
				@selected = selected
			end

			def selected?
				@selected
			end

			def status
				@status ||= helpers.status_presentation(row.state, delivered: row.delivered)
			end

			# Selects this order in the hub's right pane via the URL (?order_id); refresh keeps it open.
			def order_path
				helpers.orders_path(tab: "buying", order_id: row.id)
			end

			def awaiting?
				row.state == Orders::States::AWAITING_FUNDING
			end

			def funding_left
				helpers.distance_of_time_in_words(Time.current, row.funding_deadline_at)
			end
		end
	end
end
