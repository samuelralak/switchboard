# frozen_string_literal: true

module Orders
	# Record a consumer's reported HTLC lock and move the order to funded, atomically. Stores only
	# observable, non-spendable data (the lock terms + the proof Ys). A re-report carrying the same proofs is
	# a no-op; one carrying different proofs is rejected (those proofs were never applied).
	class Funding < BaseService
		option :order
		option :mint_url, type: Types::Strict::String
		option :hashlock, type: Types::Strict::String.optional, default: -> { } # absent for a Tier-2 P2PK lock
		option :locktime
		option :lock_pubkey, type: Types::Strict::String
		option :refund_pubkey, type: Types::Strict::String
		option :proofs, type: Types::Strict::Array
		option :arbiter_pubkey, type: Types::Strict::String.optional, default: -> { }
		option :required_signatures, type: Types::Coercible::Integer, default: -> { 1 }
		option :required_refund_signatures, type: Types::Coercible::Integer, default: -> { 1 }

		def call
			return idempotent_result! if order.current_state == Orders::States::FUNDED

			ensure_awaiting_funding!
			ensure_tier_available!
			validate!
			verify_unspent!
			Order.transaction { record_lock_and_fund! }
			order
		rescue ActiveRecord::RecordNotUnique
			idempotent_result! # a concurrent funding won the lock/proofs
		end

		private

		def ensure_awaiting_funding!
			return if order.current_state == Orders::States::AWAITING_FUNDING

			raise IllegalTransitionError, "cannot fund a #{order.current_state} order"
		end

		# A Tier-2 order can only be funded once the platform arbiter key is provisioned (the lock is built
		# against it; without it a dispute could never be ruled).
		def ensure_tier_available!
			return unless order.tier2?
			return if Escrow::ArbiterSigner.configured?

			raise ValidationError, { tier: [ "tier-2 arbiter escrow is not available" ] }
		end

		# A re-report (or a concurrent winner) is idempotent ONLY if the order is funded with exactly the
		# proofs this report carries; otherwise this report's proofs were never applied and returning success
		# would orphan them silently, so raise instead.
		def idempotent_result!
			order.reload
			return order if funded_with_reported_proofs?

			raise ValidationError, { proofs: [ "this order was already funded with different proofs" ] }
		end

		def funded_with_reported_proofs?
			order.current_state == Orders::States::FUNDED && order.proofs.pluck(:proof_y).sort == proof_ys.sort
		end

		# The reported lock must match the order (FundingContract) and the proofs must sum to the amount.
		def validate!
			result = FundingContract.new(order:).call(contract_input)
			raise ValidationError, result.errors(full: true).to_h unless result.success?
			raise ValidationError, { proofs: [ "must sum to the order amount" ] } unless proofs_sum == order.amount_sats
		end

		# A fresh lock's proofs are UNSPENT, so this rejects replayed/already-spent proofs. The mint only
		# tracks SPENT proofs, so UNSPENT cannot prove a fabricated Y is a real token: non-custodially Rails
		# cannot verify proof validity; the PROVIDER verifies the redeemable token before delivering (funded is
		# a tracking signal, not a payment guarantee).
		def verify_unspent!
			return if Cashu::Checkstate.call(mint_url:, ys: proof_ys).all?(&:unspent?)

			raise ValidationError, { proofs: [ "must be unspent at the mint" ] }
		end

		def record_lock_and_fund!
			order.create_lock!(lock_terms.merge(amount_sats: order.amount_sats))
			reported_proofs.each do |p|
				order.proofs.create!(proof_y: p[:y], amount_sats: p[:amount], keyset_id: p[:keyset_id])
			end
			Orders::Transition.call(order:, to: Orders::States::FUNDED, metadata: { "source" => "funding_report" })
		end

		# The reported proofs, symbol-keyed once.
		def reported_proofs = @reported_proofs ||= proofs.map(&:symbolize_keys)
		def proof_ys = reported_proofs.pluck(:y)
		def proofs_sum = reported_proofs.sum { |p| p[:amount].to_i }

		# The lock terms, shared by the contract check and the persisted OrderLock. Tier-1 carries a hashlock +
		# no arbiter; Tier-2 carries the arbiter + no hashlock (the absent field is nil here).
		def lock_terms
			{
				mint_url:, hashlock:, lock_pubkey:, refund_pubkey:, locktime: locktime_at,
				arbiter_pubkey:, required_signatures:, required_refund_signatures:
			}
		end

		# Pass the FULL terms (nils included) so the per-tier contract rules fire on a missing hashlock/arbiter
		# rather than silently skipping a dropped key. The Tier-2 arbiter is VALIDATED (== the platform key, in
		# both FundingContract and the OrderLock model invariant), not injected: the lock already exists at the
		# mint, so overwriting the reported key with the platform key would only HIDE a mismatch (an honestly
		# reported wrong arbiter must be rejected, not silently rewritten). The provider independently verifies
		# the real on-mint lock before working, which is the ultimate backstop. See docs/tier2-arbiter-escrow.md.
		def contract_input
			lock_terms
		end

		# locktime arrives as a Time (Ruby callers) or unix-seconds (the funding form sends an integer string).
		def locktime_at = @locktime_at ||= unix_locktime? ? Time.at(locktime.to_i).utc : locktime
		def unix_locktime? = locktime.is_a?(Numeric) || locktime.to_s.match?(/\A\d+\z/)
	end
end
