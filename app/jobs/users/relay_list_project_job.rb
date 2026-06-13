# frozen_string_literal: true

module Users
	# Projects a pubkey's current NIP-65 (kind:10002) relay list into user_relays. Enqueued from
	# Events::Upsert when a kind:10002 is stored, so a transient projection failure is a retryable queued
	# job rather than a lost after_commit side effect. Re-reads the current winner (replaceable, one per
	# pubkey), so it is idempotent and always projects the latest list (mirrors Users::ProjectJob).
	class RelayListProjectJob < ApplicationJob
		queue_as :ingest

		def perform(pubkey)
			event = Event.of_kind(Events::Kinds::RELAY_LIST).by_author(pubkey).first
			if event
				RelayListUpsert.call(event_data: event.raw_event)
			else
				# No kind:10002 remains (e.g. a NIP-09 deletion): clear the now-sourceless relay projection,
				# symmetric with Users::ProjectJob clearing a deleted profile.
				UserRelay.where(pubkey:).delete_all
			end
		end
	end
end
