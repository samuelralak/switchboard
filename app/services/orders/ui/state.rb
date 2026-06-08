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

			def self.strip(order:) = Strip.new(order:)
			def self.lifecycle(order:) = Chain.new(order:)
		end
	end
end
