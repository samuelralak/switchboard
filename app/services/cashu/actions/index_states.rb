# frozen_string_literal: true

module Cashu
	module Actions
		# Parse a NUT-07 checkstate body into a Y(lowercased) => raw-state map. Rejects a non-array states
		# field or duplicate Ys (a last-wins duplicate could flip a state). Raises MintError on any malformed
		# body, so a settlement is never inferred from a bad response.
		class IndexStates < BaseService
			option :body, type: Types::Strict::String

			def call
				states = parse_states
				keys = states.map { |state| state["Y"]&.downcase }
				raise MintError, "duplicate proof states" if keys.uniq.length != keys.length

				keys.zip(states).to_h
			end

			private

			def parse_states
				states = JSON.parse(body)["states"]
				raise MintError, "malformed checkstate body" unless states.is_a?(Array)

				states
			rescue JSON::ParserError => e
				raise MintError, "malformed checkstate body: #{e.message}"
			end
		end
	end
end
