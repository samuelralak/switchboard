# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
	test "requires a 64-hex pubkey" do
		assert User.new(pubkey: SecureRandom.hex(32), first_seen_at: Time.current).valid?
		assert_not User.new(pubkey: "npub1xyz", first_seen_at: Time.current).valid?
		assert_not User.new(pubkey: "g" * 64, first_seen_at: Time.current).valid?
		assert_not User.new(pubkey: SecureRandom.hex(32).upcase, first_seen_at: Time.current).valid?
	end

	test "enforces one row per pubkey at the database level" do
		pubkey = SecureRandom.hex(32)
		User.create!(pubkey:)

		assert_raises(ActiveRecord::RecordNotUnique) { User.create!(pubkey:) }
	end

	test "external_identities must be an array" do
		user = User.new(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, external_identities: { "x" => 1 })

		assert_not user.valid?
		assert_includes user.errors[:external_identities], "must be an array"
	end

	test "display prefers display_name, then name, then npub" do
		user = User.new(pubkey: SecureRandom.hex(32))
		assert_equal user.npub, user.display

		user.name = "alice"
		assert_equal "alice", user.display

		user.display_name = "Alice A."
		assert_equal "Alice A.", user.display
	end

	test "npub encodes the pubkey as bech32" do
		assert_match(/\Anpub1[0-9a-z]+\z/, User.new(pubkey: SecureRandom.hex(32)).npub)
	end

	test "catalog_view accepts nil or a known view and rejects others" do
		base = { pubkey: SecureRandom.hex(32), first_seen_at: Time.current }

		assert User.new(**base, catalog_view: nil).valid?
		assert User.new(**base, catalog_view: "all").valid?
		assert User.new(**base, catalog_view: "verified").valid?
		assert_not User.new(**base, catalog_view: "bogus").valid?
	end

	test "catalog_view survives a kind-0 re-projection" do
		pubkey = SecureRandom.hex(32)
		user = User.create!(pubkey:, first_seen_at: Time.current, catalog_view: "all")

		Users::Upsert.call(event_data: {
			"id" => SecureRandom.hex(32), "pubkey" => pubkey, "created_at" => Time.current.to_i,
			"kind" => 0, "content" => { "name" => "alice" }.to_json, "tags" => []
		})

		assert_equal "alice", user.reload.name
		assert_equal "all", user.catalog_view
	end

	test "listings are this pubkey's active classified events" do
		pubkey = SecureRandom.hex(32)
		mine = build_event(kind: Events::Kinds::CLASSIFIED, d: "a")
		mine.update!(pubkey:)
		build_event(kind: Events::Kinds::CLASSIFIED, d: "b")
		user = User.create!(pubkey:)

		ids = user.listings.pluck(:event_id)
		assert_includes ids, mine.event_id
		assert_equal 1, ids.size
	end
end
