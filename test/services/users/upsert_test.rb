# frozen_string_literal: true

require "test_helper"

module Users
	class UpsertTest < ActiveSupport::TestCase
		test "projects a kind-0 into a new user row" do
			event = kind0(content: { "name" => "alice", "nip05" => "alice@x.com" })

			user = Users::Upsert.call(event_data: event)

			assert_equal event["pubkey"], user.pubkey
			assert_equal "alice", user.name
			assert_equal event["id"], user.metadata_event_id
			assert_equal 1, User.where(pubkey: event["pubkey"]).count
		end

		test "keeps the newest kind-0 per pubkey" do
			pubkey = SecureRandom.hex(32)
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "old" }, created_at: 100))
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "new" }, created_at: 200))

			assert_equal "new", User.find_by(pubkey:).name
		end

		test "ignores an older kind-0" do
			pubkey = SecureRandom.hex(32)
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "current" }, created_at: 200))
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "stale" }, created_at: 100))

			assert_equal "current", User.find_by(pubkey:).name
		end

		test "breaks a created_at tie by keeping the lower id" do
			pubkey = SecureRandom.hex(32)
			higher = kind0(pubkey:, content: { "name" => "higher" }, created_at: 500, id: "b" * 64)
			lower  = kind0(pubkey:, content: { "name" => "lower" }, created_at: 500, id: "a" * 64)

			Users::Upsert.call(event_data: higher)
			Users::Upsert.call(event_data: lower)

			user = User.find_by(pubkey:)
			assert_equal "lower", user.name
			assert_equal "a" * 64, user.metadata_event_id
		end

		test "a same-created_at event with a higher id does not supersede" do
			pubkey = SecureRandom.hex(32)
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "lower" }, created_at: 500, id: "a" * 64))
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "higher" }, created_at: 500, id: "b" * 64))

			user = User.find_by(pubkey:)
			assert_equal "lower", user.name
			assert_equal "a" * 64, user.metadata_event_id
		end

		test "is idempotent for a repeated event" do
			event = kind0(content: { "name" => "alice" })
			Users::Upsert.call(event_data: event)

			assert_nothing_raised { Users::Upsert.call(event_data: event) }
			assert_equal 1, User.where(pubkey: event["pubkey"]).count
		end

		test "projects onto a bare row created by FindOrCreate" do
			pubkey = SecureRandom.hex(32)
			Users::FindOrCreate.call(pubkey:)
			Users::Upsert.call(event_data: kind0(pubkey:, content: { "name" => "filled" }, created_at: 100))

			assert_equal "filled", User.find_by(pubkey:).name
			assert_equal 1, User.where(pubkey:).count
		end

		test "retries and supersedes when it loses a cold insert race for the pubkey" do
			pubkey = SecureRandom.hex(32)
			existing = User.create!(pubkey:, nostr_created_at: Time.at(100).utc, metadata_event_id: "c" * 64)
			newer = kind0(pubkey:, content: { "name" => "newer" }, created_at: 200)

			# Force the first lookup to miss (fresh row), so create! collides with the existing
			# row and the RecordNotUnique retry takes the warm (lock + supersede) path.
			upsert = Users::Upsert.new(event_data: newer)
			missed = false
			upsert.define_singleton_method(:locked_user) do
				next User.where(pubkey:).lock.first if missed

				missed = true
				User.new(pubkey:)
			end

			user = upsert.call
			assert_equal existing.id, user.id
			assert_equal "newer", user.name
			assert_equal 1, User.where(pubkey:).count
		end

		test "tolerates malformed kind-0 content" do
			event = kind0(content: {}).merge("content" => "not json")

			user = Users::Upsert.call(event_data: event)

			assert_nil user.name
		end

		private

		def kind0(content:, tags: [], created_at: Time.now.to_i, pubkey: SecureRandom.hex(32), id: SecureRandom.hex(32))
			{
				"id" => id, "pubkey" => pubkey, "sig" => SecureRandom.hex(64),
				"kind" => Events::Kinds::METADATA, "created_at" => created_at,
				"tags" => tags, "content" => content.to_json
			}
		end
	end

	# Real threads + real commits, so the row lock and bounded retry are exercised against
	# the DB rather than a stubbed single-threaded path.
	class UpsertConcurrencyTest < ActiveSupport::TestCase
		self.use_transactional_tests = false

		teardown { User.delete_all }

		test "the newer kind-0 wins under concurrent projection (the row lock prevents lost updates)" do
			20.times do
				pubkey = SecureRandom.hex(32) # fresh per iteration, so iterations cannot collide
				Users::FindOrCreate.call(pubkey:) # a bare warm row the threads contend over

				# Spawn the winner (200) FIRST so it commits early: only the row lock can then
				# force the later, lower-created_at threads to re-read and decline. Three workers
				# plus the main thread stay within the connection pool of five.
				[ 200, 150, 100 ].map do |created_at|
					Thread.new do
						event = kind0(pubkey:, content: { "name" => created_at.to_s }, created_at:)
						ActiveRecord::Base.connection_pool.with_connection { Users::Upsert.call(event_data: event) }
					end
				end.each(&:join)

				assert_equal "200", User.find_by(pubkey:).name
			end
		end

		test "raises after exhausting retries on a perpetual insert collision" do
			pubkey = SecureRandom.hex(32)
			User.create!(pubkey:, nostr_created_at: Time.at(100).utc, metadata_event_id: "c" * 64)

			upsert = Users::Upsert.new(event_data: kind0(pubkey:, content: { "name" => "x" }, created_at: 200))
			attempts = 0
			upsert.define_singleton_method(:locked_user) do
				attempts += 1
				User.new(pubkey:) # never locks the existing row, so save! always collides
			end

			assert_raises(ActiveRecord::RecordNotUnique) { upsert.call }
			assert_equal 3, attempts
		end

		private

		def kind0(content:, created_at:, pubkey: SecureRandom.hex(32), id: SecureRandom.hex(32))
			{
				"id" => id, "pubkey" => pubkey, "sig" => SecureRandom.hex(64),
				"kind" => Events::Kinds::METADATA, "created_at" => created_at,
				"tags" => [], "content" => content.to_json
			}
		end
	end
end
