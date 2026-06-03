# frozen_string_literal: true

require "test_helper"

module Users
	class ProjectJobTest < ActiveSupport::TestCase
		test "projects the pubkey's current kind-0 into a user" do
			pubkey = SecureRandom.hex(32)
			store_kind0(pubkey:, name: "alice")

			Users::ProjectJob.perform_now(pubkey)

			assert_equal "alice", User.find_by(pubkey:).name
		end

		test "is a no-op when the pubkey has no kind-0" do
			pubkey = SecureRandom.hex(32)

			Users::ProjectJob.perform_now(pubkey)

			assert_nil User.find_by(pubkey:)
		end

		private

		def store_kind0(pubkey:, name:, created_at: 100)
			raw = {
				"id" => SecureRandom.hex(32), "pubkey" => pubkey, "sig" => SecureRandom.hex(64),
				"kind" => Events::Kinds::METADATA, "created_at" => created_at,
				"tags" => [], "content" => { "name" => name }.to_json
			}
			Event.create!(
				event_id: raw["id"], pubkey:, sig: raw["sig"], kind: raw["kind"],
				content: raw["content"], tags: [], nostr_created_at: Time.at(created_at).utc, raw_event: raw
			)
		end
	end
end
