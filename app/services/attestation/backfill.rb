# frozen_string_literal: true

module Attestation
	# One-time, idempotent backfill: attest the existing conforming listings/requests the catalog surfaces, so the
	# verified default does not hide listings published before attestation shipped (the interim trigger only
	# attests new publishes). Each event is isolated so one error does not abort the run. Requires publish
	# connections (the caller opens them; see lib/tasks/attestation.rake). Returns { attested:, failed: }.
	class Backfill < BaseService
		option :manager, default: -> { NostrClient.manager }

		def call
			return { attested: 0, failed: 0 } unless Policy.issuing?

			tally = { attested: 0, failed: 0 }
			attestable_scope.find_each do |event|
				next unless conforming?(event)

				outcome = attest(event)
				tally[outcome] += 1 if tally.key?(outcome)
			end

			tally
		end

		private

		# :attested (new label), :skipped (already attested), or :failed (logged and stepped over).
		def attest(event)
			Issue.call(event:, manager:) ? :attested : :skipped
		rescue StandardError => e
			Rails.logger.warn("[attestation:backfill] skipped #{event.event_id}: #{e.class}: #{e.message}")

			:failed
		end

		# The same set the catalog and board surface: active, published, non-flagged classified events.
		def attestable_scope
			Event.classified.active.not_unpublished.not_from_flagged
		end

		def conforming?(event)
			Catalog::Listing.new(event).conforms? || Requests::OpenRequest.new(event).conforms?
		end
	end
end
