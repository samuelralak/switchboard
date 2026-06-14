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

			# Compact time left to fund for the row's top-right slot ("2h" / "3d" / "45m"), matching the brevity
			# of the selling row's timestamp; past-due reads "now".
			def funding_left
				seconds = (row.funding_deadline_at - Time.current).to_i
				return "now" if seconds <= 0
				return "#{seconds / 86_400}d" if seconds >= 86_400
				return "#{seconds / 3_600}h" if seconds >= 3_600

				"#{[ seconds / 60, 1 ].max}m"
			end

			# Relative age for the row's top-right slot once funded (mirrors the provider inbox's "X ago").
			def created
				"#{helpers.time_ago_in_words(row.created_at)} ago"
			end
		end
	end
end
