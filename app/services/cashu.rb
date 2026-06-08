# frozen_string_literal: true

# Cashu (NUT-07/11/14) shared constants + errors for the escrow services and models. Operations live in
# Cashu::Checkstate and Cashu::Actions (no module_function helpers; see [[switchboard-service-organization]]).
module Cashu
	POINT = /\A0[23][a-f0-9]{64}\z/ # compressed secp256k1 point (a proof Y or a P2PK pubkey)

	# A mint was unreachable or returned a bad response; callers retry, never infer a settlement.
	class MintError < ServiceError; end
end
