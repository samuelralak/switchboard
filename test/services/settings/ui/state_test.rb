# frozen_string_literal: true

require "test_helper"

module Settings
	module Ui
		class StateTest < ActiveSupport::TestCase
			test "profile assembles the editor context for a user" do
				user = User.create!(pubkey: "a" * 64, first_seen_at: Time.current, external_identities: [])

				profile = Settings::Ui::State.profile(user:)

				assert_equal user, profile.user
				assert_equal "a" * 64, profile.pubkey
				assert_equal NostrClient.configuration.relays, profile.publish_relays
				assert_nil profile.metadata_event
			end

			test "profile carries the user's kind-0 as the merge base" do
				pk = "b" * 64
				User.create!(pubkey: pk, first_seen_at: Time.current, external_identities: [])
				event = metadata_event(pubkey: pk) # one per pubkey: the replaceable-coordinate index dedups kind-0

				profile = Settings::Ui::State.profile(user: User.find_by(pubkey: pk))

				assert_equal event.event_id, profile.metadata_event.event_id
			end

			private

			def metadata_event(pubkey:)
				Event.create!(
					event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
					kind: Events::Kinds::METADATA, content: "{}", tags: [],
					nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
				)
			end
		end
	end
end
