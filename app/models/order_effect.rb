# frozen_string_literal: true

# A settled-once record for an order. DB UNIQUE(order_id) is the real guard.
class OrderEffect < ApplicationRecord
	belongs_to :order, inverse_of: :effects

	validates :kind, inclusion: { in: Orders::States::SETTLEMENTS }
end
