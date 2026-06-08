# frozen_string_literal: true

# The provider's observable assertion that they delivered the result: the delivery gift-wrap event id, its
# timestamp, and a content-hash commitment. One per order (DB UNIQUE(order_id) is the real guard), superseded
# on re-delivery. Holds only observable data; the result itself travels end-to-end over NIP-17, never here.
class OrderDelivery < ApplicationRecord
	belongs_to :order, inverse_of: :delivery

	validates :delivery_event_id, :content_hash, format: { with: Events::Kinds::HEX64 }
	validates :delivered_at, presence: true
end
