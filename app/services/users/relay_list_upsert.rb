# frozen_string_literal: true

module Users
	# Projects a pubkey's NIP-65 (kind:10002) relay list into user_relays. Mirrors Users::Upsert, but the
	# NIP-01 winner is the kind:10002 already kept by Events::Upsert, so this is winner-GUARDED: it projects
	# only when the event it was handed is still the stored winner (a stale job whose list was superseded
	# skips), then rebuilds the pubkey's rows WHOLESALE (so a removed relay simply is not re-inserted, and a
	# list that drops to zero write relays correctly leaves none). The browser/server agree on one canonical
	# url via Shared::NormalizeRelayUrl; a junk url is dropped; an oversized (likely hostile) list stores none.
	class RelayListUpsert < BaseService
		option :event_data, type: Types::Strict::Hash

		def call
			UserRelay.transaction do
				next unless current_winner? # a superseded (stale) list must not overwrite the newest projection

				UserRelay.where(pubkey:).delete_all
				relay_rows.each { |row| UserRelay.create!(row.merge(base_attributes)) }
			end
		rescue ActiveRecord::RecordNotUnique
			# A concurrent projection of the same pubkey raced the delete+insert; re-drive against the winner.
			@attempts = @attempts.to_i + 1
			retry if @attempts < 3

			raise
		end

		private

		def pubkey = event_data["pubkey"]

		# The kind:10002 Events::Upsert currently holds for this pubkey is the single replaceable winner.
		def current_winner?
			winner = Event.of_kind(Events::Kinds::RELAY_LIST).by_author(pubkey).first
			winner && winner.event_id == event_data["id"]
		end

		def base_attributes
			{ pubkey:, relay_list_event_id: event_data["id"], nostr_created_at: Time.zone.at(event_data["created_at"].to_i) }
		end

		# Parse the r-tags into { url, read, write } rows (unmarked = both), normalized + deduped, dropping
		# the unsafe/invalid. A list larger than the cap is hostile/misconfigured, so it projects nothing.
		def relay_rows
			tags = event_data.fetch("tags", []).select { |tag| tag.is_a?(Array) && tag.first == UserRelay::RELAY_TAG }
			return [] if tags.length > UserRelay::MAX_RELAY_TAGS

			tags.filter_map { |tag| row_for(tag) }.uniq { |row| row[:url] }
		end

		# One { url, read, write } row from an r-tag, or nil if the url is unusable. Per NIP-65 an unmarked
		# r-tag is BOTH read and write; a "read"/"write" marker restricts it. The faithful role is stored as
		# advertised -- the per-user DIAL budget is applied later, in Relays::DesiredSet, never here, so the
		# stored list always reflects what the user actually publishes to / reads from.
		def row_for(tag)
			url = Shared::NormalizeRelayUrl.call(url: tag[1])
			return unless url

			marker = tag[2]
			read = marker.blank? || marker == UserRelay::READ_MARKER
			write = marker.blank? || marker == UserRelay::WRITE_MARKER
			return unless read || write

			{ url:, read:, write: }
		end
	end
end
