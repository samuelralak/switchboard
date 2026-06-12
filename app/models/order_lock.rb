# frozen_string_literal: true

# Non-custodial escrow terms for a funded order. Observable, non-spendable: a hash, public keys, a locktime,
# an amount. Never a secret, proof, preimage, or private key.
class OrderLock < ApplicationRecord
	belongs_to :order, inverse_of: :lock

	validates :mint_url, presence: true
	validates :hashlock, format: { with: Events::Kinds::HEX64 }, allow_nil: true # absent for a Tier-2 P2PK lock
	validates :lock_pubkey, :refund_pubkey, format: { with: Cashu::POINT }
	validates :arbiter_pubkey, format: { with: Cashu::POINT }, allow_nil: true
	validates :locktime, presence: true
	validates :amount_sats, numericality: { only_integer: true, greater_than: 0 }
	validates :required_signatures, :required_refund_signatures,
		numericality: { only_integer: true, greater_than_or_equal_to: 1 }

	# Tier shape backs the funding contract so a direct create cannot bypass it: a Tier-1 lock carries a
	# hashlock and no arbiter; a Tier-2 lock carries the PLATFORM arbiter (never a client-chosen one) and no
	# preimage gate.
	validate :tier_lock_shape

	private

	def tier_lock_shape
		return unless order

		order.tier2? ? validate_tier2_lock : validate_tier1_lock
	end

	def validate_tier2_lock
		return if arbiter_pubkey.present? && arbiter_pubkey == Escrow::ArbiterSigner.pubkey

		errors.add(:arbiter_pubkey, "must be the platform arbiter for a tier-2 lock")
	end

	def validate_tier1_lock
		errors.add(:hashlock, "is required for a tier-1 lock") if hashlock.blank?
		errors.add(:arbiter_pubkey, "must be absent for a tier-1 lock") if arbiter_pubkey.present?
	end
end
