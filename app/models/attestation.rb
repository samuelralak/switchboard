# frozen_string_literal: true

# Platform attestation domain vocabulary. The hosted platform vouches for a listing it published by signing a
# NIP-32 label (kind 1985) over the listing's coordinate; the catalog then badges (or, strictly, surfaces only)
# attested listings so a fork cannot fake "Listed on Switchboard". These constants are the single home for the
# attestation vocabulary; services and models read them rather than hardcoding strings.
module Attestation
	# NIP-32 label value, in our namespace, that means "published through the hosted platform".
	LABEL_VALUE = "listed"

	# Base of the env-scoped label namespace (prod bare, other envs suffixed), so non-prod labels never
	# validate in prod. Mirrors the listing marker scheme.
	NAMESPACE_BASE = "switchboard"

	# Catalog policies: the operator's DEFAULT catalog view (a viewer can override it per Attestation::VIEWS).
	# off disables the feature (no badges, no filter); badge defaults visitors to seeing everything (attested
	# items badged); exclude defaults them to verified-only. Defaults to exclude (fail closed: vouched-for items
	# first), overridable per-deploy via ENV and at runtime by the operator (AttestationSetting precedence).
	POLICIES       = %w[off badge exclude].freeze
	DEFAULT_POLICY = "exclude"

	# A viewer's catalog view: all listings, or only platform-attested ones. The operator policy sets the
	# default (badge -> all, exclude -> verified); each viewer can override it (Attestation::Policy.default_view,
	# the on-catalog filter, and the saved per-account preference).
	VIEWS = %w[all verified].freeze

	# The issuing key, read from ENV: a dedicated attestation key, or R_op as the fallback (reuse the platform's
	# existing operational identity). Touched only by Attestation::IssuerIdentity.
	KEY_ENV          = "ATTESTATION_PRIVATE_KEY"
	FALLBACK_KEY_ENV = "R_OP_PRIVATE_KEY"
end
