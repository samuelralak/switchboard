# frozen_string_literal: true

# A NUT-07 Y of a funded order's locked proof: enough to observe state at the mint, never to spend.
class OrderProof < ApplicationRecord
	belongs_to :order, inverse_of: :proofs

	validates :proof_y, format: { with: Cashu::POINT }, uniqueness: true
	validates :amount_sats, numericality: { only_integer: true, greater_than: 0 }
end
