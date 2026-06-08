# frozen_string_literal: true

# One active catalog order per (consumer, listing). Mirrors index_orders_active_claim_per_request:
# a consumer who orders the same service again while an order is still open lands back on that order
# rather than opening a duplicate the provider sees twice. A new order is allowed once the prior one
# terminates (released/refunded/expired), so it drops out of the partial index.
class AddActiveCatalogOrderUniqueIndex < ActiveRecord::Migration[8.1]
	def change
		add_index :orders, %i[consumer_pubkey listing_coordinate], unique: true,
			where: "entry_point = 'catalog_order' AND current_state IN ('awaiting_funding', 'funded')",
			name: "index_orders_active_order_per_consumer"
	end
end
