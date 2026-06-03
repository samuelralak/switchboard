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

ActiveRecord::Schema[8.1].define(version: 2026_06_03_142223) do
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

  create_table "login_challenges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "nonce", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_login_challenges_on_expires_at"
    t.index ["nonce"], name: "index_login_challenges_on_nonce", unique: true
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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

  add_foreign_key "sessions", "users"
end
