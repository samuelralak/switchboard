# frozen_string_literal: true

# An opaque NIP-59 gift wrap (kind 1059) deposited for a recipient, so the recipient can fetch a
# resumable inbox on cold start (and across devices) even if it was offline when the message was
# sent. The server NEVER decrypts it -- it holds no user key -- and learns no more than a relay
# would: the recipient pubkey, an ephemeral sender pubkey, a randomized timestamp, and ciphertext.
# Deposited anonymously (preserving the gift wrap's sender-hiding) and served only to the
# authenticated recipient.
class InboxWrap < ApplicationRecord
	RETENTION = 30.days
	# Cap how many live wraps one recipient may accumulate, so the open deposit cannot be used to
	# exhaust storage by flooding a single inbox. Identity-free anti-abuse (never a cookie).
	PER_RECIPIENT_QUOTA = 10_000

	scope :for_recipient, ->(pubkey) { where(recipient_pubkey: pubkey) }
	scope :unexpired, -> { where(expires_at: Time.current..) }
	scope :chronological, -> { order(:created_at, :id) }
	# Keyset cursor: strictly after the (created_at, id) the client last saw. The id tiebreaker means
	# wraps sharing a created_at are never skipped at a page boundary (a plain created_at cursor would).
	scope :after_cursor, ->(time, id) { time && id ? where("(created_at, id) > (?, ?::uuid)", time, id) : all }

	validates :recipient_pubkey, :wrap_id, format: { with: /\A[a-f0-9]{64}\z/ }
	validates :wrap, presence: true

	# Drop wraps past their retention horizon (anti-abuse / storage hygiene; run by a reaper).
	def self.prune_expired = where(expires_at: ..Time.current).delete_all
end
