# frozen_string_literal: true

module Users
	# Fetches a pubkey's kind-0 (metadata) profile event from relays and returns the NIP-01 winner, read-only
	# (no key needed: the event self-signs over its own pubkey). The relay I/O is a bounded one-shot fan-out
	# (Relays::FetchEvents); this layer keeps only OUR pubkey's metadata events and picks the latest. nil if
	# none arrived in time. The demand-side twin of Users::RelayListFetch (same shape, kind-0 instead of 10002).
	class MetadataFetch < BaseService
		DEFAULT_TIMEOUT = 5

		option :pubkey, type: Types::Strict::String
		option :relays, default: -> { NostrClient.configuration.indexer_relays }
		option :timeout, default: -> { DEFAULT_TIMEOUT }

		def call
			pick(Relays::FetchEvents.call(relays:, filters: [ filter ], timeout:))
		end

		private

		# NIP-01 winner among OUR pubkey's metadata events: highest created_at, then lexicographically lower id.
		def pick(events)
			mine = events.select { |event| event["pubkey"] == pubkey && event["kind"] == Events::Kinds::METADATA }
			mine.min_by { |event| [ -event["created_at"].to_i, event["id"].to_s ] }
		end

		def filter = { kinds: [ Events::Kinds::METADATA ], authors: [ pubkey ], limit: 1 }
	end
end
