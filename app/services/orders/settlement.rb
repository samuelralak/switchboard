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

		# A Tier-2 direction follows the signature count + who COULD have signed (the mint reports HOW MANY
		# signed, not WHO), anchored on the one fact Rails owns: the platform arbiter signs ONLY after a ruling
		# (Orders::ArbiterSign gates on dispute.ruled?), so its signature is unobtainable until then.
		#   - A single-signature spend is the consumer's timeout refund -- always a REFUND, even after a ruling,
		#     because the funds demonstrably moved back to the consumer (the loser front-running a ruling is the
		#     documented locktime-lead limitation; the label still tracks where the money went).
		#   - A quorum (2-of-3) spend on a RULED dispute is the arbiter co-signing for the ruled side (for the
		#     provider -> RELEASED; for the consumer -> REFUNDED).
		#   - A quorum spend with NO ruling can only be consumer + provider (the arbiter could not have signed),
		#     i.e. the consumer co-signed to authorize the provider: a RELEASE. (A dispute cannot be opened once
		#     a release is recorded, so a ruling never collides with an already-authorized release.)
		def arbiter_outcome(spent)
			return Orders::States::REFUNDED unless quorum_spent?(spent)
			return ruling_outcome if order.dispute&.ruled?

			Orders::States::RELEASED
		end

		def quorum_spent?(spent)
			spent.all? { |s| witness(s)[:signatures].size >= 2 }
		end

		def ruling_outcome
			order.dispute.ruled_for_provider? ? Orders::States::RELEASED : Orders::States::REFUNDED
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
