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

ActiveRecord::Schema[8.1].define(version: 2026_06_03_102606) do
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
end
