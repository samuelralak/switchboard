# frozen_string_literal: true

# The provider's observable delivery assertion for an order: the delivery gift-wrap event id, its timestamp,
# and a content-hash commitment. One row per order (UNIQUE), superseded on re-delivery. Stores ONLY
# observable data (brief 6.3) -- never the result, which travels end-to-end over NIP-17. Deliberately NOT a
# state-machine state: current_state stays funded, so settlement/refund mechanics are untouched.
class CreateOrderDeliveries < ActiveRecord::Migration[8.1]
	def change
		create_table :order_deliveries, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: { unique: true }
			t.string :delivery_event_id, limit: 64, null: false
			t.datetime :delivered_at, null: false
			t.string :content_hash, limit: 64, null: false
			t.timestamps
		end

		hex = "^[a-f0-9]{64}$"
		add_check_constraint :order_deliveries, "delivery_event_id ~ '#{hex}'", name: "order_deliveries_event_id_hex"
		add_check_constraint :order_deliveries, "content_hash ~ '#{hex}'", name: "order_deliveries_content_hash_hex"
	end
end
