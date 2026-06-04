# frozen_string_literal: true

require "securerandom"

module Messages
	module Actions
		# A unix timestamp randomized uniformly within the last TWO_DAYS (NIP-59: seal and wrap
		# created_at SHOULD be tweaked into the past to thwart time-analysis; some relays drop
		# future-dated events, so the result is NEVER in the future). Called once per layer so
		# the seal and each wrap draw independent values.
		class RandomPastTimestamp < BaseService
			TWO_DAYS = 2 * 24 * 60 * 60

			option :now, type: Types::Strict::Integer, default: -> { Time.now.to_i }

			def call
				now - SecureRandom.random_number(TWO_DAYS + 1)
			end
		end
	end
end
