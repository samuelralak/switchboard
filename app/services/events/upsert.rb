# frozen_string_literal: true

module Events
	# Persists a verified event per NIP-01 storage semantics:
	#   regular     -> append (unique on event_id)
	#   replaceable -> keep the newest per (pubkey, kind)
	#   addressable -> keep the newest per (pubkey, kind, d_tag)   [NIP-99 listings]
	# Newest = higher created_at, then the lexicographically lower id. Returns the
	# stored Event, or nil when we already hold an equal/newer copy, including a
	# duplicate or a concurrent writer that won the same id/coordinate.
	class Upsert < BaseService
		option :event_data, type: Types::Strict::Hash
		option :source_relay, type: Types::Strict::String.optional, default: -> { }

		def call
			Event.transaction do |txn|
				replace_existing_event!(coordinate) if coordinate.present?

				event = Event.create!(attributes)

				txn.after_commit { project(event) }

				event
			end
		rescue ActiveRecord::RecordNotUnique
			# Lost the race to first-insert this coordinate: retry so the committed row is
			# locked and superseded by created_at. A bare event_id duplicate has no
			# coordinate to supersede, so it stays nil.
			@attempts = @attempts.to_i + 1
			retry if coordinate.present? && @attempts < 3

			nil
		rescue ActiveRecord::RecordInvalid => e
			raise unless e.record.errors.of_kind?(:event_id, :taken)

			nil # we already hold this event_id
		end

		private

		# After commit (the row is already saved, so a failure here is loud, not a swallowed side effect):
		# broadcast a listing to its live surface, and project the per-pubkey kind-0 / kind:10002 (each
		# job re-reads the current winner, so it is idempotent). A NIP-09 deletion actions its targets.
		def project(event)
			return process_deletion(event) if event.kind == Kinds::DELETION

			broadcast_classified(event) if event.kind == Kinds::CLASSIFIED
			Users::ProjectJob.perform_later(event.pubkey) if event.kind == Kinds::METADATA
			Users::RelayListProjectJob.perform_later(event.pubkey) if event.kind == Kinds::RELAY_LIST
		end

		# NIP-09: honor a kind-5 by removing the events it references via `e` (event id) and `a`
		# (kind:pubkey:d coordinate) tags, but ONLY those authored by the SAME pubkey -- a relay must never
		# let one pubkey delete another's events. Deleting the row stops it being served (the catalog/profile
		# read live from the DB); a deleted kind-0/kind:10002 re-runs its projection job, which clears the
		# now-sourceless profile/relay projection. (A re-sent copy could re-appear; durable deletion tracking
		# is a follow-up, not needed for the erasure guarantee on content we currently hold.)
		def process_deletion(deletion)
			targets = deletion_targets(deletion)
			return if targets.empty?

			# All-or-nothing across the e/a target set: a mid-loop failure must not leave a NIP-09 deletion
			# half-applied (some referenced events erased, others permanently served). The re-sync side effects
			# (job enqueues / live-board removal) run AFTER the destroys commit, so a queue hiccup cannot strand
			# a partially-applied erasure either.
			Event.transaction { targets.each(&:destroy) }
			targets.each { |target| resync_after_delete(target) }
		end

		def deletion_targets(deletion)
			by_id = Event.by_author(deletion.pubkey).where(event_id: deletion.tag_values("e")).to_a
			by_coordinate = deletion.tag_values("a").flat_map { |a| events_for_a_tag(a, deletion.pubkey) }

			(by_id + by_coordinate).uniq(&:id)
		end

		# Same-author events at a NIP-09 `a` coordinate. Addressable coordinates carry a d (the listing id);
		# replaceable kinds (kind-0 / kind:10002) are one-per-pubkey with a stored d_tag of NULL, so match on
		# (pubkey, kind) and ignore the empty d.
		def events_for_a_tag(a_tag, pubkey)
			kind, author, d_tag = a_tag.split(":", 3)
			return [] unless author == pubkey

			kind = kind.to_i
			scope = Kinds.addressable?(kind) ? Event.where(pubkey:, kind:, d_tag: d_tag.to_s) : Event.where(pubkey:, kind:)
			scope.to_a
		end

		# Re-sync whatever projection the now-deleted event fed, so deleted content stops being served: clear the
		# sourceless profile / relay-list projection, and drop a deleted listing's card from open live boards.
		def resync_after_delete(event)
			case event.kind
			when Kinds::METADATA   then Users::ProjectJob.perform_later(event.pubkey)
			when Kinds::RELAY_LIST then Users::RelayListProjectJob.perform_later(event.pubkey)
			when Kinds::CLASSIFIED then broadcast_classified(event, visible: false)
			end
		end

		# Route a kind-30402 event to the right live surface by its marker: an open request to the demand
		# board, everything else to the supply catalog. Requests and listings share the kind, so the marker
		# is the only discriminator (mirrors the Catalog::Search / Requests::Search scope split).
		# visible: nil lets the Update decide (active/open AND author not flagged); visible: false forces a
		# remove-only broadcast (a deleted listing dropping off open boards).
		def broadcast_classified(event, visible: nil)
			if event.tag_values("t").include?(Requests::OpenRequest.marker)
				Requests::Ui::Update.call(event:, visible:)
			else
				Catalog::Ui::Update.call(event:, visible:)
			end
		end

		# Destroys the stored event at this coordinate; rolls back the transaction
		# when the incoming event does not supersede it.
		def replace_existing_event!(coordinate)
			current = Event.where(**coordinate).lock.order(nostr_created_at: :desc).first
			return unless current

			raise ActiveRecord::Rollback unless supersedes?(current)

			current.destroy
		end

		# Uniqueness coordinate for replaceable/addressable kinds; nil for regular.
		def coordinate
			pubkey = event_data["pubkey"]
			kind = event_data["kind"]

			case Kinds.classification(kind)
			when :addressable then { pubkey:, kind:, d_tag: }
			when :replaceable then { pubkey:, kind: }
			end
		end

		# NIP-01 tie-break: a newer created_at wins; on an exact tie, the lower id wins.
		def supersedes?(current)
			incoming = event_data["created_at"].to_i
			held = current.nostr_created_at.to_i
			held < incoming || (held == incoming && current.event_id > event_data["id"])
		end

		def d_tag
			tag = event_data["tags"]&.find { |t| t.is_a?(Array) && t[0] == "d" && !t[1].nil? }
			tag ? tag[1].to_s : ""
		end

		def attributes
			{
				event_id: event_data["id"],
				pubkey: event_data["pubkey"],
				kind: event_data["kind"],
				source_relay:,
				sig: event_data["sig"],
				content: event_data["content"].to_s,
				tags: event_data["tags"] || [],
				nostr_created_at: Time.at(event_data["created_at"].to_i).utc,
				raw_event: event_data.slice(*Event::WIRE_KEYS) # canonical wire fields only (no relay-appended bloat)
			}
		end
	end
end
