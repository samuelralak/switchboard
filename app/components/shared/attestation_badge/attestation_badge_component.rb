# frozen_string_literal: true

module Shared
	module AttestationBadge
		# The platform-attestation verified mark: a small copper shield shown inline on detail pages and the
		# settings previews for a kind-30402 the platform has vouched for (`label` names it for AT/hover). Cards
		# use the copper edge spine instead. Renders nothing unless attested, so callers stay unconditional.
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
