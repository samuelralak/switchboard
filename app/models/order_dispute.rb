# frozen_string_literal: true

# A Tier-2 dispute on an order: who opened it, an optional reason, and the platform arbiter's ruling. One per
# order (DB UNIQUE). Observable data only (brief 6.3); the arbiter signature is produced on demand at ruling
# time and handed to the winning party, never stored.
class OrderDispute < ApplicationRecord
	belongs_to :order, inverse_of: :dispute

	validates :opened_by_pubkey, format: { with: Events::Kinds::HEX64 }
	validates :status, inclusion: { in: Orders::DisputeStatuses::ALL }

	# Open disputes the operator has yet to rule, oldest first (the ruling queue).
	scope :awaiting_ruling, -> { where(status: Orders::DisputeStatuses::OPEN).order(created_at: :asc) }

	def open?
		status == Orders::DisputeStatuses::OPEN
	end

	def ruled?
		Orders::DisputeStatuses::RULED.include?(status)
	end

	def ruled_for_provider?
		status == Orders::DisputeStatuses::RULED_FOR_PROVIDER
	end

	def ruled_for_consumer?
		status == Orders::DisputeStatuses::RULED_FOR_CONSUMER
	end
end
