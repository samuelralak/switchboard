# frozen_string_literal: true

# The consumer's observable assertion that they released the escrow: the preimage-reveal gift-wrap event id
# and its timestamp. One row per order (UNIQUE), superseded if re-revealed. Stores ONLY observable data
# (brief 6.3) -- NEVER the preimage, which travels end-to-end over NIP-17 and is never seen by the runtime.
# Deliberately NOT a state-machine state: current_state stays funded (the mint stays authoritative for the
# settled "released" state), so settlement/refund mechanics and the reconcile sweep are untouched.
class CreateOrderReleases < ActiveRecord::Migration[8.1]
	def change
		create_table :order_releases, id: :uuid do |t|
			t.references :order, null: false, foreign_key: true, type: :uuid, index: { unique: true }
			t.string :reveal_event_id, limit: 64, null: false
			t.datetime :released_at, null: false
			t.timestamps
		end

		add_check_constraint :order_releases, "reveal_event_id ~ '^[a-f0-9]{64}$'", name: "order_releases_event_id_hex"
	end
end
