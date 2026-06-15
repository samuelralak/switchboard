# frozen_string_literal: true

module Shared
	module AttestationBadge
		# The platform-attestation verified mark: a small copper shield-with-check shown inline by the title on
		# cards, detail pages, and settings previews for a kind-30402 the platform has vouched for (`label` names
		# it for AT/hover; it pops on card hover). Renders nothing unless attested, so callers stay unconditional.
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
