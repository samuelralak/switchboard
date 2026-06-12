# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_11_210832) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.string "d_tag", limit: 255
    t.string "event_id", limit: 64, null: false
    t.datetime "expires_at"
    t.datetime "first_seen_at"
    t.integer "kind", null: false
    t.datetime "nostr_created_at", null: false
    t.string "pubkey", limit: 64, null: false
    t.jsonb "raw_event", default: {}, null: false
    t.string "sig", limit: 128, null: false
    t.string "source_relay"
    t.jsonb "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_events_on_event_id", unique: true
    t.index ["expires_at"], name: "index_events_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["kind"], name: "index_events_on_kind"
    t.index ["nostr_created_at"], name: "index_events_on_nostr_created_at"
    t.index ["pubkey", "kind", "d_tag"], name: "index_events_on_addressable_coordinate", unique: true, where: "(d_tag IS NOT NULL)"
    t.index ["pubkey", "kind"], name: "index_events_on_pubkey_and_kind"
    t.index ["pubkey", "kind"], name: "index_events_on_replaceable_coordinate", unique: true, where: "((kind = 0) OR (kind = 3) OR ((kind >= 10000) AND (kind < 20000)))"
    t.index ["tags"], name: "index_events_on_tags", using: :gin
    t.check_constraint "event_id::text ~ '^[a-f0-9]{64}$'::text", name: "events_event_id_hex"
    t.check_constraint "kind >= 0 AND kind <= 65535", name: "events_kind_range"
    t.check_constraint "pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "events_pubkey_hex"
    t.check_constraint "sig::text ~ '^[a-f0-9]{128}$'::text", name: "events_sig_hex"
  end

  create_table "inbox_wraps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "nostr_created_at", null: false
    t.string "recipient_pubkey", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.jsonb "wrap", default: {}, null: false
    t.string "wrap_id", limit: 64, null: false
    t.index ["expires_at"], name: "index_inbox_wraps_on_expires_at"
    t.index ["recipient_pubkey", "created_at", "id"], name: "index_inbox_wraps_on_recipient_pubkey_and_created_at_and_id"
    t.index ["wrap_id"], name: "index_inbox_wraps_on_wrap_id", unique: true
    t.check_constraint "recipient_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "inbox_wraps_recipient_pubkey_hex"
    t.check_constraint "wrap_id::text ~ '^[a-f0-9]{64}$'::text", name: "inbox_wraps_wrap_id_hex"
  end

  create_table "login_challenges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "nonce", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_login_challenges_on_expires_at"
    t.index ["nonce"], name: "index_login_challenges_on_nonce", unique: true
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.string "recipient_pubkey", null: false
    t.datetime "seen_at"
    t.datetime "updated_at", null: false
    t.index ["recipient_pubkey", "created_at"], name: "index_notifications_on_recipient_pubkey_and_created_at"
    t.index ["recipient_pubkey", "seen_at"], name: "index_notifications_on_recipient_pubkey_and_seen_at"
  end

  create_table "order_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "content_hash", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at", null: false
    t.string "delivery_event_id", limit: 64, null: false
    t.uuid "order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_deliveries_on_order_id", unique: true
    t.check_constraint "content_hash::text ~ '^[a-f0-9]{64}$'::text", name: "order_deliveries_content_hash_hex"
    t.check_constraint "delivery_event_id::text ~ '^[a-f0-9]{64}$'::text", name: "order_deliveries_event_id_hex"
  end

  create_table "order_effects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", limit: 32, null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_effects_on_order_id", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['released'::character varying, 'refunded'::character varying]::text[])", name: "order_effects_kind"
  end

  create_table "order_locks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "amount_sats", null: false
    t.string "arbiter_pubkey", limit: 66
    t.datetime "created_at", null: false
    t.string "hashlock", limit: 64
    t.string "lock_pubkey", limit: 66, null: false
    t.datetime "locktime", null: false
    t.string "mint_url", limit: 512, null: false
    t.uuid "order_id", null: false
    t.string "refund_pubkey", limit: 66, null: false
    t.integer "required_refund_signatures", default: 1, null: false
    t.integer "required_signatures", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_locks_on_order_id", unique: true
    t.check_constraint "amount_sats > 0", name: "order_locks_amount_positive"
    t.check_constraint "arbiter_pubkey IS NULL OR arbiter_pubkey::text ~ '^0[23][0-9a-f]{64}$'::text", name: "order_locks_arbiter_pubkey_point"
    t.check_constraint "hashlock IS NULL OR hashlock::text ~ '^[0-9a-f]{64}$'::text", name: "order_locks_hashlock_hex"
    t.check_constraint "lock_pubkey::text ~ '^0[23][0-9a-f]{64}$'::text", name: "order_locks_lock_pubkey_point"
    t.check_constraint "refund_pubkey::text ~ '^0[23][0-9a-f]{64}$'::text", name: "order_locks_refund_pubkey_point"
    t.check_constraint "required_refund_signatures >= 1", name: "order_locks_refund_sigs_positive"
    t.check_constraint "required_signatures >= 1", name: "order_locks_sigs_positive"
  end

  create_table "order_proofs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "amount_sats", null: false
    t.datetime "created_at", null: false
    t.string "keyset_id", limit: 66
    t.uuid "order_id", null: false
    t.string "proof_y", limit: 66, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_proofs_on_order_id"
    t.index ["proof_y"], name: "index_order_proofs_on_proof_y", unique: true
    t.check_constraint "amount_sats > 0", name: "order_proofs_amount_positive"
    t.check_constraint "proof_y::text ~ '^0[23][0-9a-f]{64}$'::text", name: "order_proofs_y_point"
  end

  create_table "order_releases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "order_id", null: false
    t.datetime "released_at", null: false
    t.string "reveal_event_id", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_releases_on_order_id", unique: true
    t.check_constraint "reveal_event_id::text ~ '^[a-f0-9]{64}$'::text", name: "order_releases_event_id_hex"
  end

  create_table "order_transitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "from_state", limit: 32, null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "most_recent", default: false, null: false
    t.uuid "order_id", null: false
    t.integer "sort_key", null: false
    t.string "to_state", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "most_recent"], name: "index_order_transitions_parent_most_recent", unique: true, where: "most_recent"
    t.index ["order_id", "sort_key"], name: "index_order_transitions_parent_sort", unique: true
    t.check_constraint "from_state::text = ANY (ARRAY['awaiting_funding'::character varying, 'funded'::character varying, 'disputed'::character varying, 'released'::character varying, 'refunded'::character varying, 'expired'::character varying]::text[])", name: "order_transitions_from_state"
    t.check_constraint "to_state::text = ANY (ARRAY['awaiting_funding'::character varying, 'funded'::character varying, 'disputed'::character varying, 'released'::character varying, 'refunded'::character varying, 'expired'::character varying]::text[])", name: "order_transitions_to_state"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "amount_sats", null: false
    t.string "consumer_pubkey", limit: 64, null: false
    t.datetime "created_at", null: false
    t.string "current_state", limit: 32, default: "awaiting_funding", null: false
    t.string "dedupe_key", limit: 255, null: false
    t.string "entry_point", limit: 32, null: false
    t.datetime "funding_deadline_at", null: false
    t.string "listing_coordinate", limit: 512, null: false
    t.string "mint_url", limit: 512, null: false
    t.string "provider_pubkey", limit: 64, null: false
    t.string "tier", limit: 32, default: "tier1_htlc", null: false
    t.datetime "updated_at", null: false
    t.index ["consumer_pubkey", "listing_coordinate"], name: "index_orders_active_order_per_consumer", unique: true, where: "(((entry_point)::text = 'catalog_order'::text) AND ((current_state)::text = ANY ((ARRAY['awaiting_funding'::character varying, 'funded'::character varying, 'disputed'::character varying])::text[])))"
    t.index ["consumer_pubkey"], name: "index_orders_on_consumer_pubkey"
    t.index ["dedupe_key"], name: "index_orders_on_dedupe_key", unique: true
    t.index ["funding_deadline_at"], name: "index_orders_funding_due", where: "((current_state)::text = 'awaiting_funding'::text)"
    t.index ["listing_coordinate"], name: "index_orders_active_claim_per_request", unique: true, where: "(((entry_point)::text = 'request_claim'::text) AND ((current_state)::text = ANY ((ARRAY['awaiting_funding'::character varying, 'funded'::character varying, 'disputed'::character varying])::text[])))"
    t.index ["provider_pubkey"], name: "index_orders_on_provider_pubkey"
    t.check_constraint "amount_sats > 0", name: "orders_amount_positive"
    t.check_constraint "consumer_pubkey::text <> provider_pubkey::text", name: "orders_parties_differ"
    t.check_constraint "consumer_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "orders_consumer_pubkey_hex"
    t.check_constraint "current_state::text = ANY (ARRAY['awaiting_funding'::character varying, 'funded'::character varying, 'disputed'::character varying, 'released'::character varying, 'refunded'::character varying, 'expired'::character varying]::text[])", name: "orders_current_state"
    t.check_constraint "entry_point::text = ANY (ARRAY['catalog_order'::character varying, 'request_claim'::character varying]::text[])", name: "orders_entry_point"
    t.check_constraint "provider_pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "orders_provider_pubkey_hex"
    t.check_constraint "tier::text = ANY (ARRAY['tier1_htlc'::character varying, 'tier2_arbiter'::character varying]::text[])", name: "orders_tier"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "user_relays", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "nostr_created_at", null: false
    t.string "pubkey", limit: 64, null: false
    t.boolean "read", default: true, null: false
    t.string "relay_list_event_id", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.boolean "write", default: true, null: false
    t.index ["pubkey", "url"], name: "index_user_relays_on_pubkey_and_url", unique: true
    t.index ["url", "pubkey"], name: "index_user_relays_on_write_url_pubkey", where: "write"
    t.check_constraint "pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "user_relays_pubkey_hex"
    t.check_constraint "relay_list_event_id::text ~ '^[a-f0-9]{64}$'::text", name: "user_relays_event_id_hex"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "about"
    t.text "banner"
    t.boolean "bot", default: false, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.jsonb "external_identities", default: [], null: false
    t.datetime "first_seen_at"
    t.boolean "flagged", default: false, null: false
    t.string "lud06"
    t.string "lud16"
    t.string "metadata_event_id", limit: 64
    t.string "name"
    t.string "nip05"
    t.boolean "nip05_verified", default: false, null: false
    t.datetime "nip05_verified_at"
    t.datetime "nostr_created_at"
    t.text "picture"
    t.string "pubkey", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.text "website"
    t.index ["name"], name: "index_users_on_name"
    t.index ["nip05"], name: "index_users_on_nip05"
    t.index ["nostr_created_at"], name: "index_users_on_nostr_created_at"
    t.index ["pubkey"], name: "index_users_on_pubkey", unique: true
    t.check_constraint "metadata_event_id IS NULL OR metadata_event_id::text ~ '^[a-f0-9]{64}$'::text", name: "users_metadata_event_id_hex"
    t.check_constraint "pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "users_pubkey_hex"
  end

  add_foreign_key "order_deliveries", "orders"
  add_foreign_key "order_effects", "orders"
  add_foreign_key "order_locks", "orders"
  add_foreign_key "order_proofs", "orders"
  add_foreign_key "order_releases", "orders"
  add_foreign_key "order_transitions", "orders"
  add_foreign_key "sessions", "users"
end
