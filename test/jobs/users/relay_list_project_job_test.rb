# frozen_string_literal: true

require "test_helper"

module Users
	class RelayListProjectJobTest < ActiveJob::TestCase
		R = Events::Kinds::RELAY_LIST

		# A faithful kind:10002 winner (raw_event id == event_id), replacing any prior list for the pubkey.
		def relay_list(pubkey:, tags:, created_at: Time.current, id: SecureRandom.hex(32))
			Event.where(pubkey:, kind: R).delete_all
			raw = { "id" => id, "pubkey" => pubkey, "created_at" => created_at.to_i, "tags" => tags }
			Event.create!(event_id: id, pubkey:, sig: "f" * 128, kind: R, tags:, nostr_created_at: created_at, raw_event: raw)
			raw
		end

		test "re-reads the winning kind:10002 for the pubkey and projects it" do
			pk = SecureRandom.hex(32)
			relay_list(pubkey: pk, tags: [ [ "r", "wss://relay.test", "write" ] ])

			Users::RelayListProjectJob.new.perform(pk)

			assert_equal [ "wss://relay.test" ], UserRelay.where(pubkey: pk).pluck(:url)
		end

		test "no-ops when the pubkey has no kind:10002" do
			pk = SecureRandom.hex(32)

			Users::RelayListProjectJob.new.perform(pk)

			assert_equal 0, UserRelay.where(pubkey: pk).count
		end
	end
end
