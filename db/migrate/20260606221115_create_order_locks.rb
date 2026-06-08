# frozen_string_literal: true

# The non-custodial escrow terms for a funded order (one per order). Stores only observable, non-spendable
# data: the hashlock (to verify a release witness), the locktime, the P2PK keys, and the amount. Never a
# secret, proof, preimage, or private key.
class CreateOrderLocks < ActiveRecord::Migration[8.1]
	def change
		create_table :order_locks, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: { unique: true }
			t.string :mint_url, limit: 512, null: false
			t.string :hashlock, limit: 64, null: false                      # sha256(preimage) hex
			t.datetime :locktime, null: false                               # refund valid at/after this time
			t.string :lock_pubkey, limit: 66, null: false                   # P2PK lock key (Tier-1: provider)
			t.string :refund_pubkey, limit: 66, null: false                 # consumer refund key
			t.string :arbiter_pubkey, limit: 66                             # Tier-2 arbiter (R_op), else null
			t.integer :required_signatures, null: false, default: 1         # NUT-11 n_sigs
			t.integer :required_refund_signatures, null: false, default: 1  # NUT-11 n_sigs_refund
			t.bigint :amount_sats, null: false

			t.timestamps
		end

		pk = "^0[23][0-9a-f]{64}$" # compressed secp256k1 point
		add_check_constraint :order_locks, "hashlock::text ~ '^[0-9a-f]{64}$'::text", name: "order_locks_hashlock_hex"
		add_check_constraint :order_locks, "lock_pubkey::text ~ '#{pk}'::text", name: "order_locks_lock_pubkey_point"
		add_check_constraint :order_locks, "refund_pubkey::text ~ '#{pk}'::text", name: "order_locks_refund_pubkey_point"
		add_check_constraint :order_locks, "arbiter_pubkey IS NULL OR arbiter_pubkey::text ~ '#{pk}'::text",
			name: "order_locks_arbiter_pubkey_point"
		add_check_constraint :order_locks, "amount_sats > 0", name: "order_locks_amount_positive"
		add_check_constraint :order_locks, "required_signatures >= 1", name: "order_locks_sigs_positive"
		add_check_constraint :order_locks, "required_refund_signatures >= 1", name: "order_locks_refund_sigs_positive"
	end
end
