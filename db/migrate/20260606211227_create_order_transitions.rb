# frozen_string_literal: true

# Append-only statesman ledger. State derives from the most_recent row. Metadata is jsonb (no serialize mixin).
# The two unique indexes reject a concurrent transition that would duplicate a sort_key or most_recent.
class CreateOrderTransitions < ActiveRecord::Migration[8.1]
	def change
		create_table :order_transitions, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: false # covered by composite below
			t.string :from_state, limit: 32, null: false
			t.string :to_state, limit: 32, null: false
			t.jsonb :metadata, default: {}, null: false
			t.integer :sort_key, null: false
			t.boolean :most_recent, null: false, default: false

			t.timestamps
		end

		add_index :order_transitions, [ :order_id, :sort_key ], unique: true, name: "index_order_transitions_parent_sort"
		add_index :order_transitions, [ :order_id, :most_recent ], unique: true, where: "most_recent",
			name: "index_order_transitions_parent_most_recent"

		states = "('awaiting_funding', 'funded', 'released', 'refunded', 'expired')"
		add_check_constraint :order_transitions, "from_state IN #{states}", name: "order_transitions_from_state"
		add_check_constraint :order_transitions, "to_state IN #{states}", name: "order_transitions_to_state"
	end
end
