# frozen_string_literal: true

module Attestation
	# Adds platform-attestation status to a kind-30402 presenter (a service listing or an open request). Both
	# are published through the hosted platform and attested the same way, so they share this one concern rather
	# than each reimplementing it. Memoized per instance; the catalog/board grids bulk-preload it via #attested=
	# (Attestation::Policy.mark) to avoid an N+1 over the cards.
	module Attestable
		extend ActiveSupport::Concern

		# Carries a current, issuer-signed kind-1985 label over THIS event?
		def attested?
			return @attested unless @attested.nil?

			@attested = Attestation::Policy.attested?(event)
		end

		attr_writer :attested
	end
end
