# frozen_string_literal: true

module Orders
	# The consumer's order ledger: every order they placed (a catalog order) or whose request was claimed and
	# funded (a request claim), newest first, as view rows joined to the on-relay service. The consumer mirror
	# of the provider's Messages inbox. Rows carry only what the ledger needs; the order page is the detail.
	class Ledger < BaseService
		option :pubkey, type: Types::Strict::String

		Row = Data.define(:id, :title, :cap, :sats, :state, :delivered, :created_at, :funding_deadline_at) do
			def active? = Orders::States::ACTIVE.include?(state)
		end

		def call
			orders = Order.as_consumer(pubkey).includes(:delivery).order(created_at: :desc).to_a
			services = Orders::ServiceFor.map_for(orders)

			orders.map { |order| row(order, services[order.id]) }
		end

		private

		def row(order, service)
			Row.new(
				id: order.id, title: service&.title || "Escrow order", cap: service&.capability,
				sats: order.amount_sats, state: order.current_state, delivered: order.delivery.present?,
				created_at: order.created_at, funding_deadline_at: order.funding_deadline_at
			)
		end
	end
end
