# frozen_string_literal: true

module Attestation
	# The platform attestation identity object: a thin model that carries IssuerIdentity (key resolution,
	# public key, signing via Events::Sign). Used by Attestation::Issue to sign labels and by Attestation::Policy
	# to know the public key to verify labels against.
	class Issuer
		include IssuerIdentity
	end
end
