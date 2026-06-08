# frozen_string_literal: true

# The settlement guard: exactly one effect per order (release XOR refund, never both, never twice).
class CreateOrderEffects < ActiveRecord::Migration[8.1]
	def change
		create_table :order_effects, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: { unique: true }
			t.string :kind, limit: 32, null: false # released | refunded
			t.jsonb :metadata, default: {}, null: false

			t.timestamps
		end

		add_check_constraint :order_effects, "kind IN ('released', 'refunded')", name: "order_effects_kind"
	end
end
