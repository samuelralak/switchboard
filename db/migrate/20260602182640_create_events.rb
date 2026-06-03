# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :uuid do |t|
      t.string   :event_id, null: false, limit: 64     # 64-hex Nostr event id
      t.string   :pubkey, null: false, limit: 64       # 64-hex author pubkey
      t.datetime :nostr_created_at, null: false         # event created_at (unix seconds -> time)
      t.integer  :kind, null: false
      t.string   :d_tag, limit: 255                      # addressable identifier (NIP-01); nil for non-addressable
      t.text     :content, null: false, default: ""
      t.string   :sig, null: false, limit: 128           # 128-hex Schnorr signature
      t.jsonb    :tags, null: false, default: []
      t.jsonb    :raw_event, null: false, default: {}    # verbatim wire event
      t.datetime :expires_at                             # NIP-40 expiration, if any
      t.datetime :first_seen_at
      t.string   :source_relay

      t.timestamps
    end

    add_index :events, :event_id, unique: true
    add_index :events, [ :pubkey, :kind ]
    # Addressable (NIP-01 30000-39999) dedupe key: one row per (pubkey, kind, d_tag).
    add_index :events, [ :pubkey, :kind, :d_tag ],
              unique: true,
              where: "d_tag IS NOT NULL",
              name: "index_events_on_addressable_coordinate"
    add_index :events, :kind
    add_index :events, :nostr_created_at
    add_index :events, :expires_at, where: "expires_at IS NOT NULL", name: "index_events_on_expires_at"
    add_index :events, :tags, using: :gin             # NIP filter queries: tags @> '[["t","..."]]'

    # NIP-01: lowercase-hex ids/pubkeys/sigs and a valid kind range.
    add_check_constraint :events, "event_id ~ '^[a-f0-9]{64}$'", name: "events_event_id_hex"
    add_check_constraint :events, "pubkey ~ '^[a-f0-9]{64}$'", name: "events_pubkey_hex"
    add_check_constraint :events, "sig ~ '^[a-f0-9]{128}$'", name: "events_sig_hex"
    add_check_constraint :events, "kind >= 0 AND kind <= 65535", name: "events_kind_range"
  end
end
