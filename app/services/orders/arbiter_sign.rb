# frozen_string_literal: true

module Orders
	# Issues the platform arbiter's detached signatures for the winning party of a RULED Tier-2 dispute, so
	# they can complete the 2-of-3 spend. A secret is signed ONLY when every gate holds:
	#   - the order is a disputed, ruled Tier-2 order;
	#   - the caller is the party the ruling favours (provider on ruled_for_provider, consumer on
	#     ruled_for_consumer);
	#   - the secret hashes (NUT-00 hash_to_curve) to one of THIS order's recorded proof Ys -- so a ruled
	#     winner cannot harvest signatures for a *different* order they share with the same counterparty.
	# The arbiter sees only the public lock secret (never C, never a key) and persists nothing (brief 6.3). Any
	# failed gate raises AuthorizationError, so the caller learns nothing about which gate failed. Returns one
	# 128-hex BIP-340 signature per submitted secret, in order.
	class ArbiterSign < BaseService
		option :order
		option :caller_pubkey, type: Types::Strict::String
		option :secrets, type: Types::Strict::Array.of(Types::Strict::String)

		def call
			raise AuthorizationError unless ruled_for_caller? && bound_secrets?

			secrets.map { |secret| arbiter.sign(secret) }
		end

		private

		def ruled_for_caller?
			ruled_dispute? && caller_pubkey == winner_pubkey
		end

		def ruled_dispute?
			order.tier2? && order.current_state == States::DISPUTED && order.dispute&.ruled?
		end

		# The single pubkey the ruling entitles to the arbiter signature (only meaningful once ruled).
		def winner_pubkey
			order.dispute.ruled_for_provider? ? order.provider_pubkey : order.consumer_pubkey
		end

		# Every submitted secret must belong to this order's proofs, and no more secrets than it has proofs (so
		# the hash_to_curve work is bounded by the order, not the request).
		def bound_secrets?
			return false if secrets.empty? || secrets.size > order_ys.size

			secrets.all? { |secret| order_ys.include?(Cashu::Actions::HashToCurve.call(secret:)) }
		end

		def order_ys
			@order_ys ||= order.proofs.pluck(:proof_y).to_set
		end

		def arbiter
			@arbiter ||= Escrow::ArbiterSigner.new
		end
	end
end
