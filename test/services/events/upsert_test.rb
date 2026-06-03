# frozen_string_literal: true

require "test_helper"

module Events
	class UpsertTest < ActiveSupport::TestCase
		test "appends a regular event and dedups a repeat by event_id" do
			data = event_data(kind: 1)

			assert_instance_of Event, Events::Upsert.call(event_data: data)
			assert_nil Events::Upsert.call(event_data: data)
			assert_equal 1, Event.where(event_id: data["id"]).count
		end

		test "keeps the newest addressable event and removes the superseded one" do
			old = addressable(created_at: 100)
			new = addressable(pubkey: old["pubkey"], d: d_of(old), created_at: 200)

			Events::Upsert.call(event_data: old)
			Events::Upsert.call(event_data: new)

			rows = Event.where(pubkey: old["pubkey"], kind: Events::Kinds::CLASSIFIED)
			assert_equal [ new["id"] ], rows.pluck(:event_id)
		end

		test "ignores an older or identical addressable event" do
			current = addressable(created_at: 200)
			Events::Upsert.call(event_data: current)

			older = addressable(pubkey: current["pubkey"], d: d_of(current), created_at: 100)
			assert_nil Events::Upsert.call(event_data: older)
			assert_nil Events::Upsert.call(event_data: current)

			assert_equal [ current["id"] ], Event.where(pubkey: current["pubkey"]).pluck(:event_id)
		end

		test "breaks a created_at tie by keeping the lower event_id" do
			higher = addressable(created_at: 1000, id: "b" * 64)
			lower  = addressable(pubkey: higher["pubkey"], d: d_of(higher), created_at: 1000, id: "a" * 64)

			Events::Upsert.call(event_data: higher)
			Events::Upsert.call(event_data: lower)

			assert_equal [ "a" * 64 ], Event.where(pubkey: higher["pubkey"]).pluck(:event_id)
		end

		test "retries and supersedes when it loses a cold insert race for the coordinate" do
			older = addressable(created_at: 100)
			newer = addressable(pubkey: older["pubkey"], d: d_of(older), created_at: 200)
			Events::Upsert.call(event_data: older)

			# Force the cold path once: the supersede check misses on the first pass, so
			# create! collides and the RecordNotUnique retry takes the warm (supersede) path.
			upsert = Events::Upsert.new(event_data: newer)
			upsert.define_singleton_method(:replace_existing_event!) do |_coordinate|
				singleton_class.send(:remove_method, :replace_existing_event!)
				nil
			end

			assert_instance_of Event, upsert.call
			assert_equal [ newer["id"] ], Event.where(pubkey: older["pubkey"]).pluck(:event_id)
		end

		test "keeps the newest replaceable event per (pubkey, kind)" do
			pubkey = SecureRandom.hex(32)
			old = event_data(kind: 10_000, pubkey:, created_at: 100)
			new = event_data(kind: 10_000, pubkey:, created_at: 200)

			Events::Upsert.call(event_data: old)
			Events::Upsert.call(event_data: new)

			assert_equal [ new["id"] ], Event.where(pubkey:, kind: 10_000).pluck(:event_id)
		end

		test "selects the d tag by its first valued entry, ignoring a value-less d tag" do
			pubkey = SecureRandom.hex(32)
			tags = [ [ "d" ], [ "d", "logo" ], [ "title", "svc" ] ]
			old = event_data(kind: Events::Kinds::CLASSIFIED, pubkey:, created_at: 100, tags:)
			new = event_data(kind: Events::Kinds::CLASSIFIED, pubkey:, created_at: 200, tags:)

			Events::Upsert.call(event_data: old)
			Events::Upsert.call(event_data: new)

			assert_equal [ new["id"] ], Event.where(pubkey:, kind: Events::Kinds::CLASSIFIED).pluck(:event_id)
		end

		private

		def addressable(pubkey: SecureRandom.hex(32), d: SecureRandom.hex(4), created_at: Time.now.to_i, id: SecureRandom.hex(32))
			event_data(kind: Events::Kinds::CLASSIFIED, pubkey:, created_at:, id:, tags: [ [ "d", d ], [ "title", "svc" ] ])
		end

		def d_of(data) = data["tags"].find { |t| t[0] == "d" }[1]

		def event_data(kind:, pubkey: SecureRandom.hex(32), tags: [], created_at: Time.now.to_i, id: SecureRandom.hex(32))
			{
				"id" => id, "pubkey" => pubkey, "sig" => SecureRandom.hex(64),
				"kind" => kind, "created_at" => created_at, "tags" => tags, "content" => "x"
			}
		end
	end

	# after_commit only fires on a real commit, so these run without the surrounding
	# test transaction.
	class UpsertBroadcastTest < ActiveSupport::TestCase
		self.use_transactional_tests = false

		teardown { Event.delete_all }

		test "broadcasts a classified listing once after the row commits" do
			ids = recording_broadcasts { Events::Upsert.call(event_data: stored(kind: Events::Kinds::CLASSIFIED)) }

			assert_equal 1, ids.size
		end

		test "does not broadcast a stored non-classified event" do
			ids = recording_broadcasts { Events::Upsert.call(event_data: stored(kind: 30_001)) }

			assert_empty ids
		end

		test "commits the row before broadcasting, so a broadcast failure cannot lose it" do
			event = stored(kind: Events::Kinds::CLASSIFIED)

			assert_raises(RuntimeError) { raising_broadcast { Events::Upsert.call(event_data: event) } }
			assert_equal 1, Event.where(event_id: event["id"]).count
		end

		private

		# Temporarily replace Catalog::Ui::Update.call with a recorder, then restore it.
		def recording_broadcasts
			recorded = []
			singleton = Catalog::Ui::Update.singleton_class
			singleton.send(:alias_method, :__orig_call, :call)
			singleton.send(:define_method, :call) { |event:| recorded << event.event_id }
			yield
			recorded
		ensure
			singleton.send(:alias_method, :call, :__orig_call)
			singleton.send(:remove_method, :__orig_call)
		end

		# Replace Catalog::Ui::Update.call with one that raises, then restore it.
		def raising_broadcast
			singleton = Catalog::Ui::Update.singleton_class
			singleton.send(:alias_method, :__orig_call, :call)
			singleton.send(:define_method, :call) { |event:| raise "broadcast boom" }
			yield
		ensure
			singleton.send(:alias_method, :call, :__orig_call)
			singleton.send(:remove_method, :__orig_call)
		end

		def stored(kind:, pubkey: SecureRandom.hex(32), d: SecureRandom.hex(4), created_at: Time.now.to_i)
			{
				"id" => SecureRandom.hex(32), "pubkey" => pubkey, "sig" => SecureRandom.hex(64),
				"kind" => kind, "created_at" => created_at, "tags" => [ [ "d", d ] ], "content" => "x"
			}
		end
	end
end
