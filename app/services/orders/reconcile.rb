# frozen_string_literal: true

module Orders
	# Re-derive a settleable order's state from the mint (NUT-07, authoritative) and settle it if the proofs
	# have moved. A no-op for non-settleable orders (funded or, for a Tier-2 dispute, disputed). Cashu::MintError
	# propagates so the caller retries.
	class Reconcile < BaseService
		option :order

		def call
			return order unless Orders::States::SETTLEABLE.include?(order.current_state)
			return order if order.lock.blank? || order.proofs.empty? # nothing observable to reconcile

			settle_from_mint
		end

		private

		def settle_from_mint
			states = Cashu::Checkstate.call(mint_url: order.lock.mint_url, ys: order.proofs.pluck(:proof_y))
			Orders::Settlement.call(order:, states:)
		end
	end
end
