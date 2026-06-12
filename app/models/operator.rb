# frozen_string_literal: true

# The platform-operator allowlist (config/initializers/operators.rb). Authorizes a signed-in pubkey for the
# admin surface; a Nostr login gated by OPERATOR_PUBKEYS, never a stored role or custodial key.
module Operator
	class << self
		def authorized?(pubkey)
			pubkey.present? && pubkeys.include?(pubkey.to_s.downcase)
		end

		def pubkeys
			Array(Rails.application.config.x.operator_pubkeys)
		end
	end
end
