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

				txn.after_commit do
					Catalog::Ui::Update.call(event:) if event.kind == Kinds::CLASSIFIED
					Users::ProjectJob.perform_later(event.pubkey) if event.kind == Kinds::METADATA
				end

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
				raw_event: event_data
			}
		end
	end
end
