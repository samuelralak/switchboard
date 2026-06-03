# frozen_string_literal: true

require "test_helper"

module Users
	class ProfilableTest < ActiveSupport::TestCase
		test "derives the standard profile fields" do
			content = {
				"name" => "alice", "display_name" => "Alice", "about" => "hi",
				"picture" => "https://x/a.png", "banner" => "https://x/b.png",
				"website" => "https://alice.example", "nip05" => "alice@example.com",
				"lud16" => "alice@wallet.example"
			}
			user = assign(content)

			assert_equal "alice", user.name
			assert_equal "Alice", user.display_name
			assert_equal "hi", user.about
			assert_equal "https://x/a.png", user.picture
			assert_equal "https://x/b.png", user.banner
			assert_equal "https://alice.example", user.website
			assert_equal "alice@example.com", user.nip05
			assert_equal "alice@wallet.example", user.lud16
		end

		test "canonicalizes deprecated aliases, but the canonical key wins" do
			user = assign({ "username" => "bob", "displayName" => "Bob", "image" => "https://x/i.png", "bio" => "yo" })
			assert_equal "bob", user.name
			assert_equal "Bob", user.display_name
			assert_equal "https://x/i.png", user.picture
			assert_equal "yo", user.about

			assert_equal "canonical", assign({ "name" => "canonical", "username" => "alias" }).name
		end

		test "blanks empty strings to nil and ignores non-string values" do
			user = assign({ "name" => "   ", "about" => 42, "picture" => nil })

			assert_nil user.name
			assert_nil user.about
			assert_nil user.picture
		end

		test "reads the bot flag only for boolean true" do
			assert assign({ "bot" => true }).bot
			assert_not assign({ "bot" => "true" }).bot
			assert_not assign({ "bot" => 1 }).bot
			assert_not assign({ "name" => "x" }).bot
		end

		test "extracts NIP-39 i tags and skips malformed ones" do
			tags = [
				[ "i", "github:alice", "proof123" ], [ "i", "twitter:bob" ], [ "i", "nokey" ],
				[ "i" ], [ "i", 123 ], [ "p", "x" ]
			]
			identities = assign({}, tags:).external_identities

			assert_equal 2, identities.size
			assert_equal({ "platform" => "github", "identity" => "alice", "proof" => "proof123" }, identities.first)
			assert_nil identities.second["proof"]
		end

		test "tolerates malformed or non-object JSON content" do
			[ "{not json", "[1,2,3]", "42", "null", "\"hi\"", "true" ].each do |body|
				user = User.new(pubkey: SecureRandom.hex(32))
				user.assign_kind0(kind0(body))

				assert_nil user.name, "#{body} should derive no name"
			end
		end

		test "records provenance" do
			event = kind0({ "name" => "x" }.to_json, created_at: 1700)
			user = User.new(pubkey: SecureRandom.hex(32))
			user.assign_kind0(event)

			assert_equal event["id"], user.metadata_event_id
			assert_equal Time.at(1700).utc, user.nostr_created_at
		end

		private

		def assign(content, tags: [])
			user = User.new(pubkey: SecureRandom.hex(32))
			user.assign_kind0(kind0(content.to_json, tags:))
			user
		end

		def kind0(content, tags: [], created_at: Time.now.to_i)
			{
				"id" => SecureRandom.hex(32), "pubkey" => SecureRandom.hex(32),
				"kind" => Events::Kinds::METADATA, "created_at" => created_at,
				"tags" => tags, "content" => content
			}
		end
	end

	# A newer kind-0 replaces the projection wholesale; these pin the cross-event update semantics.
	class ProfilableUpdateTest < ActiveSupport::TestCase
		test "a sparse newer kind-0 blanks fields a prior one set (wholesale replace, not merge)" do
			full = { "name" => "a", "about" => "hi", "website" => "https://a.x" }
			user = User.new(pubkey: SecureRandom.hex(32))
			user.assign_kind0(kind0(full.to_json, tags: [ [ "i", "x:y" ] ]))
			user.assign_kind0(kind0({ "name" => "a" }.to_json))

			assert_equal "a", user.name
			assert_nil user.about
			assert_nil user.website
			assert_equal [], user.external_identities
		end

		test "a changed nip05 clears prior verification, an unchanged one keeps it" do
			user = User.create!(pubkey: SecureRandom.hex(32))
			user.assign_kind0(kind0({ "nip05" => "a@x.com" }.to_json, created_at: 100))
			user.update!(nip05_verified: true, nip05_verified_at: Time.current)

			user.assign_kind0(kind0({ "nip05" => "a@x.com" }.to_json, created_at: 200))
			assert user.nip05_verified, "unchanged nip05 keeps verification"

			user.assign_kind0(kind0({ "nip05" => "b@y.com" }.to_json, created_at: 300))
			assert_not user.nip05_verified, "changed nip05 clears verification"
		end

		private

		def kind0(content, tags: [], created_at: Time.now.to_i)
			{
				"id" => SecureRandom.hex(32), "pubkey" => SecureRandom.hex(32),
				"kind" => Events::Kinds::METADATA, "created_at" => created_at,
				"tags" => tags, "content" => content
			}
		end
	end
end
