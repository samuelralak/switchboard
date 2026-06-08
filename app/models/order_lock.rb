# frozen_string_literal: true

# Non-custodial escrow terms for a funded order. Observable, non-spendable: a hash, public keys, a locktime,
# an amount. Never a secret, proof, preimage, or private key.
class OrderLock < ApplicationRecord
	belongs_to :order, inverse_of: :lock

	validates :mint_url, presence: true
	validates :hashlock, format: { with: Events::Kinds::HEX64 }
	validates :lock_pubkey, :refund_pubkey, format: { with: Cashu::POINT }
	validates :arbiter_pubkey, format: { with: Cashu::POINT }, allow_nil: true
	validates :locktime, presence: true
	validates :amount_sats, numericality: { only_integer: true, greater_than: 0 }
	validates :required_signatures, :required_refund_signatures,
		numericality: { only_integer: true, greater_than_or_equal_to: 1 }
end
