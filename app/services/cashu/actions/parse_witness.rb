# frozen_string_literal: true

require "json"

module Cashu
	module Actions
		# Parse a NUT-14 HTLC witness (a JSON string, or an already-decoded object) into
		# { preimage:, signatures: }. Blank-, malformed-, and wrong-type-safe: a missing, unparseable, or
		# non-object witness yields a nil preimage rather than raising, so a misbehaving mint cannot crash
		# settlement.
		class ParseWitness < BaseService
			option :witness

			def call
				return none if witness.blank?

				parsed = witness.is_a?(String) ? JSON.parse(witness) : witness
				return none unless parsed.is_a?(Hash) # a non-object witness carries no preimage

				{ preimage: parsed["preimage"], signatures: parsed["signatures"] || [] }
			rescue JSON::ParserError => e
				Rails.logger.warn("[Cashu] unparseable witness: #{e.message}")
				none
			end

			private

			def none = { preimage: nil, signatures: [] }
		end
	end
end
