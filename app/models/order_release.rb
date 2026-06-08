# frozen_string_literal: true

# The consumer's observable assertion that they released the escrow: the preimage-reveal gift-wrap event id
# and its timestamp. One per order (DB UNIQUE(order_id) is the real guard), superseded if re-revealed. Holds
# only observable data; the preimage itself travels end-to-end over NIP-17, never here.
class OrderRelease < ApplicationRecord
	belongs_to :order, inverse_of: :release

	validates :reveal_event_id, format: { with: Events::Kinds::HEX64 }
	# released_at is the consumer's reveal time (the NIP-17 rumor created_at). Reject only absurd values: a
	# generous past bound for any timestamp jitter, a small future tolerance for clock skew. Keeps a nonsense
	# year off the timeline; this row is observational, never a settlement input.
	validates :released_at, presence: true, inclusion: { in: -> { 7.days.ago..1.hour.from_now } }
end
