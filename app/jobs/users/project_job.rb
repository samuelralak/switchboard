# frozen_string_literal: true

module Users
	# Projects a pubkey's current kind-0 (metadata) profile onto its User row. Enqueued from
	# Events::Upsert when a kind-0 is stored, so a transient projection failure becomes a
	# retryable queued job rather than a lost after_commit side effect. Re-reads the current
	# kind-0 (replaceable, one per pubkey), so it is idempotent and always projects the winner.
	class ProjectJob < ApplicationJob
		queue_as :ingest

		def perform(pubkey)
			event = Event.of_kind(Events::Kinds::METADATA).by_author(pubkey).first
			if event
				Upsert.call(event_data: event.raw_event)
			else
				# No kind-0 remains (e.g. a NIP-09 deletion): erase the stale profile projection rather than
				# leaving deleted personal data served. No-op when there is nothing projected yet.
				User.find_by(pubkey:)&.clear_profile!
			end
		end
	end
end
