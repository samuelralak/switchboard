# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string   :pubkey, null: false, limit: 64        # 64-hex identity (canonical key)

      # Denormalized kind-0 (NIP-01/NIP-24) metadata; all nullable, "" -> nil on derive.
      t.string   :name
      t.string   :display_name
      t.text     :about
      t.text     :picture
      t.text     :banner
      t.text     :website
      t.boolean  :bot, null: false, default: false

      # NIP-05 internet identifier + cached, re-checkable verification (never trusted from content).
      t.string   :nip05
      t.boolean  :nip05_verified, null: false, default: false
      t.datetime :nip05_verified_at

      # Lightning zap addresses (stored only; resolution is a client concern).
      t.string   :lud16                                  # LUD-16 lightning address
      t.string   :lud06                                  # LUD-06 bech32 LNURL

      # NIP-39 external identities from the kind-0 `i` tags: [{platform, identity, proof}].
      t.jsonb    :external_identities, null: false, default: []

      # Provenance / freshness (parallels the Event model).
      t.string   :metadata_event_id, limit: 64           # the winning kind-0's events.event_id
      t.datetime :nostr_created_at                        # kind-0 created_at; nil until a kind-0 is seen
      t.datetime :first_seen_at

      t.boolean  :flagged, null: false, default: false    # moderation flag

      t.timestamps
    end

    add_index :users, :pubkey, unique: true
    add_index :users, :nip05                              # non-unique: nip05 is spoofable
    add_index :users, :name                               # non-unique: name is spoofable
    add_index :users, :nostr_created_at

    # Same lowercase-hex discipline as events.
    add_check_constraint :users, "pubkey ~ '^[a-f0-9]{64}$'", name: "users_pubkey_hex"
    add_check_constraint :users, "metadata_event_id IS NULL OR metadata_event_id ~ '^[a-f0-9]{64}$'",
                         name: "users_metadata_event_id_hex"
  end
end
