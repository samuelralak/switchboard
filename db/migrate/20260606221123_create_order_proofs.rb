# frozen_string_literal: true

# The NUT-07 Y values of a funded order's locked proofs: enough to OBSERVE state at the mint, never enough to
# spend (no secret, no signature C). proof_y is globally unique, so a proof funds at most one order.
class CreateOrderProofs < ActiveRecord::Migration[8.1]
	def change
		create_table :order_proofs, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid
			t.string :proof_y, limit: 66, null: false # Y = hash_to_curve(secret), compressed point
			t.bigint :amount_sats, null: false
			t.string :keyset_id, limit: 64

			t.timestamps
		end

		add_index :order_proofs, :proof_y, unique: true
		add_check_constraint :order_proofs, "proof_y::text ~ '^0[23][0-9a-f]{64}$'::text", name: "order_proofs_y_point"
		add_check_constraint :order_proofs, "amount_sats > 0", name: "order_proofs_amount_positive"
	end
end
