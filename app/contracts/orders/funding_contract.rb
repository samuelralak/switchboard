# frozen_string_literal: true

require "dry/validation"

module Orders
	# Validates a consumer's reported lock against the order, PER TIER. Tier-1 (HTLC): a hashlock + a provider
	# lock key, no arbiter. Tier-2 (2-of-3 P2PK arbiter): no hashlock, an arbiter key that MUST equal the
	# platform arbiter key (a consumer-chosen arbiter would let the consumer hold 2-of-3 and drain the lock),
	# n_sigs=2, and a locktime far enough out for a dispute to resolve. Hex/point formats, a future + capped
	# locktime, and an allowlisted mint apply to both. The proof Y values and amount sum are checked in the
	# service (structural), backed by the OrderProof/OrderLock model + DB constraints.
	class FundingContract < ApplicationContract
		option :order

		params do
			required(:mint_url).filled(:string)
			optional(:hashlock).maybe(:string)
			required(:lock_pubkey).filled(:string)
			required(:refund_pubkey).filled(:string)
			required(:locktime).filled(:time)
			optional(:arbiter_pubkey).maybe(:string)
			optional(:required_signatures).filled(:integer)
			optional(:required_refund_signatures).filled(:integer)
		end

		rule(:mint_url) do
			key.failure("does not match the order mint") unless value == order.mint_url
			key.failure("mint not allowlisted") unless Orders::Policy.mint_allowed?(value)
		end

		# Tier-1 needs a 64-hex hashlock; Tier-2 (P2PK, no preimage) must not carry one.
		rule(:hashlock) do
			if order.tier2?
				key.failure("must be absent for a tier-2 lock") if value.present?
			elsif value.blank?
				key.failure("is required for a tier-1 lock")
			elsif !Events::Kinds::HEX64.match?(value)
				key.failure("must be 64 lowercase hex")
			end
		end

		rule(:lock_pubkey) { key.failure("must be a compressed point") unless Cashu::POINT.match?(value) }
		rule(:refund_pubkey) { key.failure("must be a compressed point") unless Cashu::POINT.match?(value) }

		# The load-bearing anti-bypass: a Tier-2 arbiter MUST be the platform key, never a client-chosen one;
		# a Tier-1 lock must carry no arbiter.
		rule(:arbiter_pubkey) do
			if order.tier2?
				key.failure("must be the platform arbiter key") unless value.present? && value == Escrow::ArbiterSigner.pubkey
			elsif value.present?
				key.failure("must be absent for a tier-1 lock")
			end
		end

		rule(:required_signatures) do
			expected = order.tier2? ? 2 : 1
			key.failure("must be #{expected} for this tier") unless (value || 1) == expected
		end

		rule(:required_refund_signatures) do
			key.failure("must be 1") unless (value || 1) == 1
		end

		rule(:locktime) do
			if value <= Time.current
				key.failure("must be in the future")
			elsif value > Orders::Policy.max_locktime.from_now
				key.failure("is too far in the future")
			elsif order.tier2? && value < Orders::Policy.tier2_min_locktime.from_now
				key.failure("must allow time for a dispute to resolve")
			end
		end
	end
end
