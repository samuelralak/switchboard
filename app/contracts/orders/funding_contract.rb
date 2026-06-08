# frozen_string_literal: true

require "dry/validation"

module Orders
	# Validates a consumer's reported HTLC lock against the order: hex/point formats, a future locktime, and a
	# mint that matches the order and is allowlisted. The proof Y values and amount sum are checked in the
	# service (structural), backed by the OrderProof/OrderLock model + DB constraints.
	class FundingContract < ApplicationContract
		option :order

		params do
			required(:mint_url).filled(:string)
			required(:hashlock).filled(:string)
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
		rule(:hashlock) { key.failure("must be 64 lowercase hex") unless Events::Kinds::HEX64.match?(value) }
		rule(:lock_pubkey) { key.failure("must be a compressed point") unless Cashu::POINT.match?(value) }
		rule(:refund_pubkey) { key.failure("must be a compressed point") unless Cashu::POINT.match?(value) }
		rule(:arbiter_pubkey) { key.failure("must be a compressed point") if value && !Cashu::POINT.match?(value) }
		rule(:locktime) do
			if value <= Time.current
				key.failure("must be in the future")
			elsif value > Orders::Policy.max_locktime.from_now
				key.failure("is too far in the future")
			end
		end
	end
end
