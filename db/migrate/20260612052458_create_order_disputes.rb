# frozen_string_literal: true

# A Tier-2 (arbiter) dispute: either party opened it on a funded order (which moved to `disputed`), and the
# platform arbiter later rules it for the provider or the consumer. One row per order (UNIQUE). Stores only
# observable data (brief 6.3): who opened it, an optional reason, and the ruling + when. The arbiter signature
# itself is never stored -- it is produced on demand at ruling time and handed to the winning party.
class CreateOrderDisputes < ActiveRecord::Migration[8.1]
	def change
		create_table :order_disputes, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: { unique: true }
			t.string :opened_by_pubkey, limit: 64, null: false
			t.text :reason
			t.string :status, limit: 32, null: false, default: "open"
			t.datetime :ruled_at

			t.timestamps
		end

		add_check_constraint :order_disputes, "opened_by_pubkey ~ '^[a-f0-9]{64}$'", name: "order_disputes_opened_by_hex"
		add_check_constraint :order_disputes,
			"status IN ('open', 'ruled_for_provider', 'ruled_for_consumer')", name: "order_disputes_status"
	end
end
