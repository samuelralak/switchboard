# frozen_string_literal: true

class CreateUserRelays < ActiveRecord::Migration[8.1]
	def change
		create_table :user_relays, id: :uuid do |t|
			t.string :pubkey, limit: 64, null: false
			t.string :url, null: false                              # normalized ws(s) URL (Shared::NormalizeRelayUrl)
			t.boolean :read, null: false, default: true
			t.boolean :write, null: false, default: true
			t.string :relay_list_event_id, limit: 64, null: false   # provenance: the kind:10002 this row came from
			t.datetime :nostr_created_at, null: false               # provenance: that event's NIP-01 created_at
			t.timestamps
		end

		# One row per (pubkey, relay); the ingest reconcile unions distinct write URLs across users, so a
		# (url) index where write keeps the coverage query (COUNT(DISTINCT pubkey) GROUP BY url) cheap.
		add_index :user_relays, %i[pubkey url], unique: true
		add_index :user_relays, %i[url pubkey], where: "write", name: "index_user_relays_on_write_url_pubkey"

		add_check_constraint :user_relays, "pubkey ~ '^[a-f0-9]{64}$'", name: "user_relays_pubkey_hex"
		add_check_constraint :user_relays, "relay_list_event_id ~ '^[a-f0-9]{64}$'", name: "user_relays_event_id_hex"
	end
end
