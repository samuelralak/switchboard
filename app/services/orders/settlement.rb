# frozen_string_literal: true

require "digest"

module Orders
	# Apply an order's settlement from a mint checkstate result. The mint confirms the proofs are SPENT (the
	# money moved, irreversibly); the DIRECTION (released vs refunded) is read per tier:
	#   - Tier-1 (HTLC): a SPENT proof whose witness reveals the lock's preimage is a RELEASE (the provider
	#     redeemed); without it, a REFUND (the consumer reclaimed after the locktime the mint enforced).
	#   - Tier-2 (2-of-3 P2PK): the mint witness cannot tell us WHO signed (Rails never sees the secret), only
	#     HOW MANY, and a hostile mint could pad that count. So a RELEASE is anchored in the consumer's own
	#     release assertion (an observable Rails record the mint cannot forge) confirmed by a main-path 2-of-3
	#     spend; the single-signature timeout and everything ambiguous is a refund. (A Slice-4 arbiter ruling
	#     refines a disputed order's direction.)
	# All UNSPENT means still funded. Runs for funded OR disputed orders (Tier-2 disputes settle from disputed).
	class Settlement < BaseService
		option :order
		option :states # Array<Cashu::ProofState>

		def call
			return order unless settleable?

			settle!
		rescue IllegalTransitionError
			# A concurrent settlement (e.g. a double-submitted settle racing the sweep) terminalized the order
			# first; its outcome is authoritative and order_effects' UNIQUE(order_id) already barred a double
			# settle, so this loser is a clean no-op rather than a 500.
			order.reload
		end

		private

		# Settle only once the order is settleable AND the mint shows every proof spent (the spend is atomic, so
		# a partial state means wait).
		def settleable?
			Orders::States::SETTLEABLE.include?(order.current_state) && states.any? && states.all?(&:spent?)
		end

		def settle!
			to = outcome(states)
			Orders::Transition.call(order:, to:, metadata: evidence(states, to))
		end

		def outcome(spent)
			order.tier2? ? arbiter_outcome(spent) : htlc_outcome(spent)
		end

		def htlc_outcome(spent)
			released_via_preimage?(spent) ? Orders::States::RELEASED : Orders::States::REFUNDED
		end

		def released_via_preimage?(spent)
			hashlock = order.lock&.hashlock
			return false if hashlock.blank?

			spent.any? { |s| preimage_matches?(witness(s)[:preimage], hashlock) }
		end

		# A release needs BOTH the consumer's release assertion (the mint cannot forge it) AND a main-path
		# 2-of-3 spend (every proof carries the two required signatures). Anything else -- the single-signature
		# timeout refund, a mixed/short witness, or a spend with no release on record -- is a refund. This is
		# conservative: it never credits a release the consumer did not assert, so a padded witness cannot
		# steal. (The label settles the order; the funds already moved at the mint either way.)
		def arbiter_outcome(spent)
			released_by_consumer?(spent) ? Orders::States::RELEASED : Orders::States::REFUNDED
		end

		def released_by_consumer?(spent)
			order.release.present? && spent.all? { |s| witness(s)[:signatures].size >= 2 }
		end

		def witness(state)
			Cashu::Actions::ParseWitness.call(witness: state.witness)
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
