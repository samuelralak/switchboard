# frozen_string_literal: true

# Platform operators: the Nostr pubkeys allowed onto the admin surface (Tier-2 dispute rulings). An allowlist,
# not a DB role -- an operator signs in with their own Nostr key like any user, and OPERATOR_PUBKEYS (comma-
# separated 64-hex) gates the admin controllers. Read by Operator. Empty by default, so the surface is closed
# until pubkeys are provisioned.
Rails.application.configure do
	pubkeys = ENV.fetch("OPERATOR_PUBKEYS", "").split(",").map { |key| key.strip.downcase }
	config.x.operator_pubkeys = pubkeys.grep(/\A[0-9a-f]{64}\z/).freeze
end
