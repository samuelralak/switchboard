# frozen_string_literal: true

module Users
	# Fetches a pubkey's NIP-65 (kind:10002) relay list from the fixed discovery indexers and returns the
	# NIP-01 winner, read-only (no key needed: the event self-signs over its own pubkey). The relay I/O is a
	# bounded one-shot fan-out (Relays::FetchEvents); this layer just keeps OUR pubkey's relay-list events
	# (a non-compliant relay's foreign-pubkey or wrong-kind events are filtered) and picks the latest. nil if
	# none arrived in time.
	class RelayListFetch < BaseService
		DEFAULT_TIMEOUT = 5

		option :pubkey, type: Types::Strict::String
		option :relays, default: -> { NostrClient.configuration.indexer_relays }
		option :timeout, default: -> { DEFAULT_TIMEOUT }

		def call
			pick(Relays::FetchEvents.call(relays:, filters: [ filter ], timeout:))
		end

		private

		# NIP-01 winner among OUR pubkey's relay-list events: highest created_at, then lexicographically lower id.
		def pick(events)
			mine = events.select { |event| event["pubkey"] == pubkey && event["kind"] == Events::Kinds::RELAY_LIST }
			mine.min_by { |event| [ -event["created_at"].to_i, event["id"].to_s ] }
		end

		def filter = { kinds: [ Events::Kinds::RELAY_LIST ], authors: [ pubkey ], limit: 1 }
	end
end
