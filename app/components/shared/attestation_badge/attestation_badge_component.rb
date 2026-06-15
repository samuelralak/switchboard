# frozen_string_literal: true

module Shared
	module AttestationBadge
		# The platform-attestation verified mark: a small copper shield-with-check shown inline by the title on
		# cards, detail pages, and settings previews for a kind-30402 the platform has vouched for (`label` names
		# it for AT/hover; it pops on card hover). Renders nothing unless attested, so callers stay unconditional.
		class AttestationBadgeComponent < ApplicationComponent
			attr_reader :label

			def initialize(attested:, label: "Listed on Switchboard", focusable: false)
				@attested = attested
				@label = label
				@focusable = focusable
			end

			def render?
				@attested
			end

			# Keyboard-reachable (tab stop + focus ring) only where the mark is not already inside an interactive
			# card; the hover/focus tooltip then reveals its meaning to keyboard users too. On cards the wrapper
			# must stay non-focusable (it lives inside the card's <button>).
			def wrapper_class
				base = "group/verified relative inline-flex shrink-0 items-center"
				return base unless @focusable

				"#{base} rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright"
			end

			def tabindex
				@focusable ? 0 : nil
			end
		end
	end
end
