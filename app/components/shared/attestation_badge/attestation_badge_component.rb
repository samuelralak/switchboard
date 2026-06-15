# frozen_string_literal: true

module Shared
	module AttestationBadge
		# The platform-attestation trust badge ("Listed on Switchboard" for a service, "Posted on Switchboard"
		# for a request), shown on a kind-30402 the hosted platform has vouched for. Renders nothing unless the
		# item is attested, so callers can render it unconditionally.
		class AttestationBadgeComponent < ApplicationComponent
			attr_reader :label

			def initialize(attested:, label: "Listed on Switchboard")
				@attested = attested
				@label = label
			end

			def render?
				@attested
			end
		end
	end
end
