# frozen_string_literal: true

module Cashu
	# NUT-07 proof-state check against a mint (server-side, observe-only): returns one Cashu::ProofState per
	# requested Y, in order. Allowlist-guards the mint, then delegates transport (Actions::PostCheckstate) and
	# parsing (Actions::IndexStates). Raises MintError on any transport/protocol failure, so a settlement is
	# never inferred from a bad response.
	class Checkstate < BaseService
		option :mint_url, type: Types::Strict::String
		option :ys, type: Types::Strict::Array.of(Types::Strict::String)

		def call
			return [] if ys.empty?

			ensure_allowlisted!
			states = Actions::IndexStates.call(body: Actions::PostCheckstate.call(mint_url:, ys:)) # Y(lc) => raw
			ys.map { |y| proof_state(y, states[y.downcase]) }
		end

		private

		def ensure_allowlisted!
			raise MintError, "mint not allowlisted: #{mint_url}" unless Orders::Policy.mint_allowed?(mint_url)
		end

		# One ProofState per requested Y; a missing Y is a protocol error (never inferred as a state).
		def proof_state(proof_y, raw)
			raise MintError, "mint returned no state for #{proof_y}" if raw.nil?

			ProofState.new(y: proof_y, state: raw["state"], witness: raw["witness"])
		end
	end
end
