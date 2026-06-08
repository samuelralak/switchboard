# frozen_string_literal: true

require "dry/validation"

module Orders
	# Validates a new escrow order: known entry_point/tier, hex parties that differ, an allowlisted mint, and a
	# positive amount within the per-order cap. The DB still enforces these as hard constraints.
	class CreateContract < ApplicationContract
		params do
			required(:entry_point).filled(:string)
			required(:consumer_pubkey).filled(:string)
			required(:provider_pubkey).filled(:string)
			required(:listing_coordinate).filled(:string)
			required(:amount_sats).filled(:integer)
			required(:mint_url).filled(:string)
			required(:dedupe_key).filled(:string)
			required(:tier).filled(:string)
			required(:funding_deadline_at).filled(:time)
		end

		rule(:entry_point) { key.failure("unknown entry point") unless Orders::EntryPoints::ALL.include?(value) }
		rule(:tier) { key.failure("unknown tier") unless Orders::Tiers::ALL.include?(value) }
		rule(:consumer_pubkey) { key.failure("must be 64 lowercase hex") unless Events::Kinds::HEX64.match?(value) }
		rule(:provider_pubkey) { key.failure("must be 64 lowercase hex") unless Events::Kinds::HEX64.match?(value) }
		rule(:mint_url) { key.failure("mint not allowlisted") unless Orders::Policy.mint_allowed?(value) }
		rule(:funding_deadline_at) { key.failure("must be in the future") unless value > Time.current }

		rule(:amount_sats) do
			if value <= 0
				key.failure("must be positive")
			elsif value > Orders::Policy.max_order_sats
				key.failure("exceeds the #{Orders::Policy.max_order_sats} sat cap")
			end
		end

		rule(:provider_pubkey, :consumer_pubkey) do
			next unless values[:provider_pubkey] == values[:consumer_pubkey]

			key(:provider_pubkey).failure("must differ from the consumer")
		end
	end
end
