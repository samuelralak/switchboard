# frozen_string_literal: true

# One relay a pubkey advertises in its NIP-65 (kind:10002) list, projected by Users::RelayListUpsert and
# kept newest-per-pubkey (wholesale-replaced on a newer list). The catalog ingest unions the distinct
# WRITE urls across users (the outbox model: a user publishes their listings to their write relays), so
# `writeable` is the set the relay:boot reconcile dials. `read`/`write` follow NIP-65: an unmarked r-tag
# is both.
class UserRelay < ApplicationRecord
	include UserRelays::Nip65

	belongs_to :user, primary_key: :pubkey, foreign_key: :pubkey, optional: true, inverse_of: :user_relays

	validates :pubkey, format: { with: Events::Kinds::HEX64 }
	validates :url, presence: true

	scope :writeable, -> { where(write: true) }
end
