# frozen_string_literal: true

require "digest"

module Orders
	# Apply an order's settlement from a mint checkstate result. A SPENT proof whose witness reveals the lock's
	# preimage is a RELEASE (the provider redeemed); a SPENT proof without it is a REFUND (the consumer
	# reclaimed after the locktime, which the mint already enforced). All UNSPENT means still funded.
	class Settlement < BaseService
		option :order
		option :states # Array<Cashu::ProofState>

		def call
			return order unless order.current_state == Orders::States::FUNDED
			return order unless states.any? && states.all?(&:spent?) # spend is atomic; a partial state means wait

			to = released?(states) ? Orders::States::RELEASED : Orders::States::REFUNDED
			Orders::Transition.call(order:, to:, metadata: evidence(states, to))
		end

		private

		def released?(spent)
			hashlock = order.lock&.hashlock
			return false if hashlock.blank?

			spent.any? { |s| preimage_matches?(Cashu::Actions::ParseWitness.call(witness: s.witness)[:preimage], hashlock) }
		end

		def preimage_matches?(preimage, hashlock)
			return false unless preimage.is_a?(String)

			normalized = preimage.downcase # a mint may echo the witness preimage in any hex case
			return false unless Events::Kinds::HEX64.match?(normalized)

			Digest::SHA256.hexdigest([ normalized ].pack("H*")) == hashlock
		rescue StandardError
			false
		end

		def evidence(spent, to)
			{ "source" => "mint_checkstate", "settled_as" => to, "spent_ys" => spent.map(&:y) }
		end
	end
end
