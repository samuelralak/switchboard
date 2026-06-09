# frozen_string_literal: true

module UserRelays
	# NIP-65 (kind:10002) relay-list vocabulary + projection policy: how an r-tag list maps to user_relays
	# rows. Included into UserRelay, so these read as UserRelay::RELAY_TAG etc.
	# https://github.com/nostr-protocol/nips/blob/master/65.md
	module Nip65
		RELAY_TAG = "r"
		WRITE_MARKER = "write"
		READ_MARKER = "read"
		MAX_RELAY_TAGS = 20 # a list larger than this is misconfigured or hostile: project nothing
	end
end
