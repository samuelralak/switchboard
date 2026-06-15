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
		include ActiveJob::TestHelper

		teardown do
			Event.delete_all
			User.delete_all
		end

		test "broadcasts a classified listing once after the row commits" do
			ids = recording_broadcasts { Events::Upsert.call(event_data: stored(kind: Events::Kinds::CLASSIFIED)) }

			assert_equal 1, ids.size
		end

		test "does not broadcast a stored non-classified event" do
			ids = recording_broadcasts { Events::Upsert.call(event_data: stored(kind: 30_001)) }

			assert_empty ids
		end

		test "routes a classified open request to the demand board, not the catalog" do
			request = stored(kind: Events::Kinds::CLASSIFIED)
			request["tags"] << [ "t", Requests::OpenRequest.marker ]

			catalog_ids = []
			board_ids = recording(Requests::Ui::Update) do
				catalog_ids = recording(Catalog::Ui::Update) { Events::Upsert.call(event_data: request) }
			end

			assert_equal [ request["id"] ], board_ids
			assert_empty catalog_ids
		end

		test "commits the row before broadcasting, so a broadcast failure cannot lose it" do
			event = stored(kind: Events::Kinds::CLASSIFIED)

			assert_raises(RuntimeError) { raising_broadcast { Events::Upsert.call(event_data: event) } }
			assert_equal 1, Event.where(event_id: event["id"]).count
		end

		test "enqueues a projection that fills the user for a stored kind-0 metadata event" do
			pubkey = SecureRandom.hex(32)
			event = stored(kind: Events::Kinds::METADATA, pubkey:)
			event["content"] = { "name" => "alice" }.to_json

			perform_enqueued_jobs { Events::Upsert.call(event_data: event) }

			user = User.find_by(pubkey:)
			assert_not_nil user
			assert_equal "alice", user.name
			assert_equal event["id"], user.metadata_event_id
		end

		test "does not enqueue a projection for a non-metadata event" do
			pubkey = SecureRandom.hex(32)

			assert_no_enqueued_jobs(only: Users::ProjectJob) do
				recording_broadcasts { Events::Upsert.call(event_data: stored(kind: Events::Kinds::CLASSIFIED, pubkey:)) }
			end
			assert_nil User.find_by(pubkey:)
		end

		test "an older kind-0 arriving second does not re-project over the newer one" do
			pubkey = SecureRandom.hex(32)
			newer = stored(kind: Events::Kinds::METADATA, pubkey:, created_at: 200)
			newer["content"] = { "name" => "newer" }.to_json
			older = stored(kind: Events::Kinds::METADATA, pubkey:, created_at: 100)
			older["content"] = { "name" => "older" }.to_json

			perform_enqueued_jobs { Events::Upsert.call(event_data: newer) }
			# The older event does not supersede, so Events::Upsert rolls back before the
			# after_commit hook: no projection job is enqueued and the projection is unchanged.
			assert_no_enqueued_jobs(only: Users::ProjectJob) { Events::Upsert.call(event_data: older) }

			assert_equal "newer", User.find_by(pubkey:).name
			assert_equal 1, Event.of_kind(Events::Kinds::METADATA).where(pubkey:).count
		end

		test "a NIP-09 deletion removes the same-author event it references by e tag" do
			pubkey = SecureRandom.hex(32)
			target = stored(kind: Events::Kinds::CLASSIFIED, pubkey:)
			perform_enqueued_jobs { Events::Upsert.call(event_data: target) }

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "e", target["id"] ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_nil Event.find_by(event_id: target["id"])
		end

		test "a NIP-09 deletion never removes an event authored by a different pubkey" do
			victim = stored(kind: Events::Kinds::CLASSIFIED) # a random, different author
			perform_enqueued_jobs { Events::Upsert.call(event_data: victim) }

			attacker = stored(kind: Events::Kinds::DELETION) # a different pubkey deleting the victim's id
			attacker["tags"] = [ [ "e", victim["id"] ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: attacker) }

			assert_not_nil Event.find_by(event_id: victim["id"])
		end

		test "a NIP-09 deletion removes the same-author addressable listing it references by a tag" do
			pubkey = SecureRandom.hex(32)
			listing = stored(kind: Events::Kinds::CLASSIFIED, pubkey:, d: "logo")
			perform_enqueued_jobs { Events::Upsert.call(event_data: listing) }

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "a", "#{Events::Kinds::CLASSIFIED}:#{pubkey}:logo" ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_equal 0, Event.classified.where(pubkey:).count
		end

		test "a NIP-09 deletion of a kind-0 erases the projected profile (GDPR right-to-erasure)" do
			pubkey = SecureRandom.hex(32)
			meta = stored(kind: Events::Kinds::METADATA, pubkey:)
			meta["content"] = { "name" => "alice" }.to_json
			perform_enqueued_jobs { Events::Upsert.call(event_data: meta) }
			assert_equal "alice", User.find_by(pubkey:).name

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "e", meta["id"] ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_nil Event.find_by(event_id: meta["id"]) # the source kind-0 is gone
			user = User.find_by(pubkey:)
			assert_nil user.name # the projection is cleared
			assert_nil user.metadata_event_id
		end

		test "a NIP-09 deletion of a kind-0 via an a tag (replaceable coordinate, empty d) still erases it" do
			pubkey = SecureRandom.hex(32)
			meta = stored(kind: Events::Kinds::METADATA, pubkey:)
			meta["content"] = { "name" => "bob" }.to_json
			meta["tags"] = [] # a real kind-0 carries no d tag (replaceable, not addressable)
			perform_enqueued_jobs { Events::Upsert.call(event_data: meta) }
			assert_equal "bob", User.find_by(pubkey:).name

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "a", "#{Events::Kinds::METADATA}:#{pubkey}:" ] ] # replaceable coordinate, empty d
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_equal 0, Event.of_kind(Events::Kinds::METADATA).where(pubkey:).count
			assert_nil User.find_by(pubkey:).name
		end

		test "a NIP-09 deletion of a kind:10002 clears the projected relay list (erasure symmetry with kind-0)" do
			pubkey = SecureRandom.hex(32)
			relays = stored(kind: Events::Kinds::RELAY_LIST, pubkey:)
			relays["tags"] = [ [ UserRelay::RELAY_TAG, "wss://relay.example.com" ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: relays) }
			assert_operator UserRelay.where(pubkey:).count, :>, 0

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "e", relays["id"] ] ]
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_equal 0, UserRelay.where(pubkey:).count
		end

		test "a NIP-09 multi-target deletion is atomic: a destroy failure rolls the whole set back" do
			pubkey = SecureRandom.hex(32)
			a = stored(kind: Events::Kinds::CLASSIFIED, pubkey:, d: "a")
			b = stored(kind: Events::Kinds::CLASSIFIED, pubkey:, d: "b")
			perform_enqueued_jobs { Events::Upsert.call(event_data: a); Events::Upsert.call(event_data: b) }

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "a", "#{Events::Kinds::CLASSIFIED}:#{pubkey}:a" ],
				[ "a", "#{Events::Kinds::CLASSIFIED}:#{pubkey}:b" ] ]

			calls = 0
			Event.class_eval do
				alias_method :__orig_destroy, :destroy
				define_method(:destroy) do
					calls += 1
					raise "destroy boom" if calls == 2

					__orig_destroy
				end
			end

			assert_raises(RuntimeError) { Events::Upsert.call(event_data: deletion) }
			# The destroys share the kind-5's transaction, so a failure rolls back BOTH: neither target is
			# destroyed AND the kind-5 is not committed, so the job retry re-applies the whole deletion (rather
			# than skipping a now-duplicate-but-unapplied kind-5).
			assert_equal 2, Event.classified.where(pubkey:).count
			assert_nil Event.find_by(event_id: deletion["id"])
		ensure
			Event.class_eval { alias_method :destroy, :__orig_destroy; remove_method :__orig_destroy }
		end

		test "a NIP-09 deletion with a malformed a-tag kind does not erase the author's own kind-0" do
			pubkey = SecureRandom.hex(32)
			meta = stored(kind: Events::Kinds::METADATA, pubkey:)
			meta["content"] = { "name" => "carol" }.to_json
			meta["tags"] = []
			perform_enqueued_jobs { Events::Upsert.call(event_data: meta) }

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "a", "abc:#{pubkey}:whatever" ] ] # non-numeric kind would to_i to 0 (kind-0)
			perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) }

			assert_equal 1, Event.of_kind(Events::Kinds::METADATA).where(pubkey:).count
			assert_equal "carol", User.find_by(pubkey:).name
		end

		test "deleting a listing broadcasts its removal to open boards" do
			pubkey = SecureRandom.hex(32)
			listing = stored(kind: Events::Kinds::CLASSIFIED, pubkey:, d: "x")
			perform_enqueued_jobs { Events::Upsert.call(event_data: listing) }

			deletion = stored(kind: Events::Kinds::DELETION, pubkey:)
			deletion["tags"] = [ [ "e", listing["id"] ] ]
			ids = recording_broadcasts { perform_enqueued_jobs { Events::Upsert.call(event_data: deletion) } }

			assert_equal [ listing["id"] ], ids
		end

		test "an attestation label rebroadcasts the listing it covers (so its badge flips on live)" do
			pubkey = SecureRandom.hex(32)
			listing = stored(kind: Events::Kinds::CLASSIFIED, pubkey:, d: "svc")
			perform_enqueued_jobs { Events::Upsert.call(event_data: listing) }

			label = stored(kind: Events::Kinds::LABEL)
			label["tags"] = [ [ "a", "#{Events::Kinds::CLASSIFIED}:#{pubkey}:svc" ], [ "e", listing["id"] ] ]
			ids = recording_broadcasts { perform_enqueued_jobs { Events::Upsert.call(event_data: label) } }

			assert_equal [ listing["id"] ], ids
		end

		private

		# Temporarily replace target.call with a recorder of broadcast event_ids, then restore it. Two
		# different targets nest cleanly (each aliases on its own singleton).
		def recording(target)
			recorded = []
			singleton = target.singleton_class
			singleton.send(:alias_method, :__orig_call, :call)
			singleton.send(:define_method, :call) { |event:, **| recorded << event.event_id }
			yield
			recorded
		ensure
			singleton.send(:alias_method, :call, :__orig_call)
			singleton.send(:remove_method, :__orig_call)
		end

		def recording_broadcasts(&) = recording(Catalog::Ui::Update, &)

		# Replace Catalog::Ui::Update.call with one that raises, then restore it.
		def raising_broadcast
			singleton = Catalog::Ui::Update.singleton_class
			singleton.send(:alias_method, :__orig_call, :call)
			singleton.send(:define_method, :call) { |**| raise "broadcast boom" }
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
