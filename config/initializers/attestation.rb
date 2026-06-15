# frozen_string_literal: true

# Platform attestation: the hosted platform vouches for a listing it published by signing a NIP-32 label
# (kind 1985) over the listing's coordinate. The catalog then badges (or, in strict mode, surfaces only)
# attested listings, so a fork cannot fake "Listed on Switchboard". Config, not code, so a self-hoster runs
# their own issuer key + policy. Read by Attestation::Policy (which normalizes + derives the rest); the signing
# key is touched only by Attestation::IssuerIdentity and is never stored here.
#
#   ATTESTATION_POLICY        off | badge | exclude   (default exclude; the operator's in-app choice overrides it)
#   ATTESTATION_PRIVATE_KEY   64-hex issuing key; falls back to R_OP_PRIVATE_KEY (reuse R_op) when unset
#   ATTESTATION_PUBKEY        64-hex issuer pubkey to verify against (for a reader with no signing key)
#   ATTESTATION_REQUIRE_FEE   true | false            (default false; the paid gate, wired with payments)
Rails.application.configure do
	config.x.attestation.policy = ENV.fetch("ATTESTATION_POLICY", "").strip.downcase
	config.x.attestation.explicit_pubkey = ENV["ATTESTATION_PUBKEY"].presence&.strip&.downcase
	config.x.attestation.require_fee = ENV.fetch("ATTESTATION_REQUIRE_FEE", "false").strip.downcase == "true"
end
