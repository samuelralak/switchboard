# frozen_string_literal: true

module Users
	# Projects a pubkey's current kind-0 (metadata) profile onto its User row. Enqueued from
	# Events::Upsert when a kind-0 is stored, so a transient projection failure becomes a
	# retryable queued job rather than a lost after_commit side effect. Re-reads the current
	# kind-0 (replaceable, one per pubkey), so it is idempotent and always projects the winner.
	class ProjectJob < ApplicationJob
		queue_as :ingest

		def perform(pubkey)
			event = Event.of_kind(Events::Kinds::METADATA).where(pubkey:).first
			Upsert.call(event_data: event.raw_event) if event
		end
	end
end
