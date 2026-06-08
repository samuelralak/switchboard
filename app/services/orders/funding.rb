# frozen_string_literal: true

module Orders
	# Record a consumer's reported HTLC lock and move the order to funded, atomically. Stores only
	# observable, non-spendable data (the lock terms + the proof Ys). A re-report carrying the same proofs is
	# a no-op; one carrying different proofs is rejected (those proofs were never applied).
	class Funding < BaseService
		option :order
		option :mint_url, type: Types::Strict::String
		option :hashlock, type: Types::Strict::String
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

		# The HTLC lock terms, shared by the contract check and the persisted OrderLock.
		def lock_terms
			{
				mint_url:, hashlock:, lock_pubkey:, refund_pubkey:, locktime: locktime_at,
				arbiter_pubkey:, required_signatures:, required_refund_signatures:
			}
		end

		def contract_input = lock_terms.compact

		# locktime arrives as a Time (Ruby callers) or unix-seconds (the funding form sends an integer string).
		def locktime_at = @locktime_at ||= unix_locktime? ? Time.at(locktime.to_i).utc : locktime
		def unix_locktime? = locktime.is_a?(Numeric) || locktime.to_s.match?(/\A\d+\z/)
	end
end
