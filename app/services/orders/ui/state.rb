# frozen_string_literal: true

module Orders
	module Ui
		# Render state for an order's live tracking page: one value object holding the stream + status-strip
		# target, shared by the page render (turbo_stream_from), the StatusStrip component, and the broadcast,
		# so all three agree on a single source. Mirrors Catalog::Ui::State.
		class State
			Strip = Data.define(:order) do
				def stream = "order_#{order.id}"
				def target = "order_#{order.id}_status"
				def broadcast = { target:, partial: "orders/status_strip", locals: { order: } }
			end

			# The order page's primary state surface (the lifecycle stepper); shares the order stream with Strip.
			Chain = Data.define(:order) do
				def stream = "order_#{order.id}"
				def target = "order_#{order.id}_lifecycle"
				def broadcast = { target:, partial: "orders/lifecycle", locals: { order: } }
			end

			# The order activity hub (OrdersController#index): a two-pane surface like the messages inbox -- the
			# signed-in user's orders by role (Buying = consumer, Selling = provider) on the left, the open order's
			# detail on the right. `open_order` is the ?order_id row or, on wide screens, the first; `selected` is
			# true only when an order_id was given (drives the narrow-screen list/detail toggle). An index surface
			# like Catalog::Ui::State.grid, composing the existing per-side queries.
			Hub = Data.define(:buying_orders, :buying_requests, :selling, :open_order, :selected, :tab) do
				def buying?
					tab == "buying"
				end

				def buying_count
					buying_orders.size + buying_requests.size
				end

				def selling_count
					selling.size
				end

				def buying_empty?
					buying_orders.empty? && buying_requests.empty?
				end
			end

			def self.strip(order:) = Strip.new(order:)
			def self.lifecycle(order:) = Chain.new(order:)

			def self.hub(pubkey:, tab: nil, order_id: nil)
				active = tab == "selling" ? "selling" : "buying"
				buying_orders = Orders::Ledger.call(pubkey:)
				selling = Messages::ProviderInbox.call(pubkey:)
				selectable = active == "selling" ? selling : buying_orders
				# A given order_id must match one of YOUR own orders; an unknown/foreign id shows nothing (no
				# fallback to the first, so a bad/stale id never silently opens an unrelated order). With no id,
				# the first opens on wide screens.
				chosen = order_id.present? ? selectable.find { |row| row.id == order_id } : selectable.first

				Hub.new(
					buying_orders:,
					buying_requests: Requests::AuthoredRequests.call(pubkey:),
					selling:,
					open_order: chosen,
					selected: order_id.present? && chosen.present?, # an explicit pick: narrow shows the detail
					tab: active
				)
			end
		end
	end
end
