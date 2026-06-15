# frozen_string_literal: true

module Events
	# Nostr event-kind constants and classification per NIP-01.
	# https://github.com/nostr-protocol/nips/blob/master/01.md
	#
	# Storage behaviour follows the kind's range:
	#   regular     -> keep every event
	#   replaceable -> keep only the latest per (pubkey, kind)
	#   addressable -> keep only the latest per (pubkey, kind, d-tag)  [NIP-99 listings are here]
	#   ephemeral   -> never stored (relayed only)
	module Kinds
		# Hex validation patterns (lowercase, per NIP-01 convention).
		HEX64  = /\A[a-f0-9]{64}\z/
		HEX128 = /\A[a-f0-9]{128}\z/

		# --- Ranges (NIP-01) ---
		REGULAR_RANGE_PRIMARY  = (1000...10_000)
		REGULAR_RANGE_LEGACY   = (4...45)
		REGULAR_STANDALONE     = [ 1, 2 ].freeze
		REPLACEABLE_RANGE      = (10_000...20_000)
		REPLACEABLE_STANDALONE = [ 0, 3 ].freeze
		EPHEMERAL_RANGE        = (20_000...30_000)
		ADDRESSABLE_RANGE      = (30_000...40_000)

		# --- Kinds relevant to Switchboard ---
		METADATA       = 0       # profile metadata (NIP-01)
		DELETION       = 5       # NIP-09
		SEAL           = 13      # NIP-59
		DIRECT_MESSAGE = 14      # NIP-17
		FILE_MESSAGE   = 15      # NIP-17
		LABEL          = 1985    # NIP-32 label event (platform listing attestation)
		NUTZAP         = 9321    # NIP-61
		ZAP_REQUEST    = 9734    # NIP-57
		ZAP            = 9735    # NIP-57
		GIFT_WRAP      = 1059    # NIP-59
		RELAY_LIST     = 10_002  # NIP-65 relay list (replaceable)
		RELAY_LIST_DM  = 10_050  # NIP-17 DM inbox relay list (replaceable)
		AUTH           = 22_242  # NIP-42 client authentication
		HTTP_AUTH      = 27_235  # NIP-98 HTTP authentication (sign-in); never persisted
		CLASSIFIED     = 30_402  # NIP-99 classified listing (the service catalog)
		HANDLER_REC    = 31_989  # NIP-89 handler recommendation
		HANDLER_INFO   = 31_990  # NIP-89 handler information

		module_function

		def regular?(kind)
			REGULAR_RANGE_PRIMARY.cover?(kind) || REGULAR_RANGE_LEGACY.cover?(kind) ||
				REGULAR_STANDALONE.include?(kind)
		end

		def replaceable?(kind)
			REPLACEABLE_RANGE.cover?(kind) || REPLACEABLE_STANDALONE.include?(kind)
		end

		def ephemeral?(kind) = EPHEMERAL_RANGE.cover?(kind)
		def addressable?(kind) = ADDRESSABLE_RANGE.cover?(kind)
		def storable?(kind) = !ephemeral?(kind)

		def classification(kind)
			return :ephemeral   if ephemeral?(kind)
			return :addressable if addressable?(kind)
			return :replaceable if replaceable?(kind)

			:regular
		end
	end
end
