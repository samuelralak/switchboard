# frozen_string_literal: true

# Escrow orders. current_state is a denormalized cache of the statesman ledger so the claim-binding partial
# index and state scopes can reference it.
class CreateOrders < ActiveRecord::Migration[8.1]
	def change
		create_table :orders, id: :uuid do |t|
			t.string :entry_point, limit: 32, null: false                       # catalog_order | request_claim
			t.string :current_state, limit: 32, null: false, default: "awaiting_funding" # cache of the ledger head
			t.string :tier, limit: 32, null: false, default: "tier1_htlc"       # tier1_htlc | tier2_arbiter
			t.string :consumer_pubkey, limit: 64, null: false                   # buyer Nostr pubkey (hex)
			t.string :provider_pubkey, limit: 64, null: false                   # seller Nostr pubkey (hex)
			t.string :listing_coordinate, limit: 512, null: false               # NIP-99 a-coord (kind:pubkey:d)
			t.bigint :amount_sats, null: false                                  # escrowed budget; cap enforced in service
			t.string :mint_url, limit: 512, null: false                         # vetted mint; allowlist enforced in service
			t.string :dedupe_key, limit: 255, null: false                       # idempotent-creation key
			t.datetime :funding_deadline_at, null: false                        # awaiting_funding window deadline

			t.timestamps
		end

		add_index :orders, :dedupe_key, unique: true
		add_index :orders, :consumer_pubkey
		add_index :orders, :provider_pubkey
		# Deadline sweep: only awaiting_funding orders can expire.
		add_index :orders, :funding_deadline_at, where: "current_state = 'awaiting_funding'", name: "index_orders_funding_due"
		# One active claim per open request (catalog orders are not exclusive, so they are excluded).
		add_index :orders, :listing_coordinate, unique: true,
			where: "entry_point = 'request_claim' AND current_state IN ('awaiting_funding', 'funded')",
			name: "index_orders_active_claim_per_request"

		add_check_constraint :orders, "entry_point IN ('catalog_order', 'request_claim')", name: "orders_entry_point"
		add_check_constraint :orders, "tier IN ('tier1_htlc', 'tier2_arbiter')", name: "orders_tier"
		add_check_constraint :orders,
			"current_state IN ('awaiting_funding', 'funded', 'released', 'refunded', 'expired')", name: "orders_current_state"
		add_check_constraint :orders, "consumer_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "orders_consumer_pubkey_hex"
		add_check_constraint :orders, "provider_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "orders_provider_pubkey_hex"
		add_check_constraint :orders, "amount_sats > 0", name: "orders_amount_positive"
	end
end
