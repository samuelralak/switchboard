# frozen_string_literal: true

class CreateInboxWraps < ActiveRecord::Migration[8.1]
	def change
		create_table :inbox_wraps, id: :uuid do |t|
			t.string :recipient_pubkey, limit: 64, null: false # the wrap's [p] tag
			t.string :wrap_id, limit: 64, null: false           # the kind-1059 event id (dedup key)
			t.jsonb :wrap, default: {}, null: false             # the opaque gift wrap, never decrypted
			t.datetime :nostr_created_at, null: false           # the wrap's (randomized) created_at
			t.datetime :expires_at, null: false                 # retention horizon for pruning

			t.timestamps
		end

		add_index :inbox_wraps, :wrap_id, unique: true
		add_index :inbox_wraps, [ :recipient_pubkey, :created_at, :id ] # recipient fetch + (created_at, id) keyset cursor
		add_index :inbox_wraps, :expires_at

		add_check_constraint :inbox_wraps, "recipient_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "inbox_wraps_recipient_pubkey_hex"
		add_check_constraint :inbox_wraps, "wrap_id::text ~ '^[a-f0-9]{64}$'::text", name: "inbox_wraps_wrap_id_hex"
	end
end
