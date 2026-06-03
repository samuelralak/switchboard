# frozen_string_literal: true

module Users
	# Projects a verified kind-0 (metadata) event onto its User row, keeping only the
	# newest per pubkey via the same NIP-01 rule Events::Upsert applies to the source
	# event: higher created_at wins, then the lexicographically lower id. Returns the User.
	class Upsert < BaseService
		option :event_data, type: Types::Strict::Hash

		def call
			User.transaction do
				user = locked_user
				if supersedes?(user)
					user.assign_kind0(event_data)
					user.save!
				end
				user
			end
		rescue ActiveRecord::RecordNotUnique
			# A concurrent projection inserted this pubkey first; re-drive to lock and supersede it.
			@attempts = @attempts.to_i + 1
			retry if @attempts < 3

			raise
		end

		private

		# Row-locks the existing projection (serializing concurrent projections of the same
		# pubkey), or returns a fresh unsaved row for a pubkey we have not seen.
		def locked_user
			User.where(pubkey: event_data["pubkey"]).lock.first || User.new(pubkey: event_data["pubkey"])
		end

		# True when the incoming kind-0 should replace what this row already holds.
		def supersedes?(user)
			return true unless user.metadata_event_id

			incoming = event_data["created_at"].to_i
			held = user.nostr_created_at.to_i
			held < incoming || (held == incoming && user.metadata_event_id > event_data["id"])
		end
	end
end
