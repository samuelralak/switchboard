# frozen_string_literal: true

module Shared
	module BackLink
		# Renders a back navigation link with a leading icon.
		class BackLinkComponent < ApplicationComponent
			LINK_CLASSES = "inline-flex items-center gap-1.5 font-mono text-xs text-ink-muted hover:text-ink " \
										"mb-6 transition-colors focus-visible:outline-none focus-visible:ring-2 " \
										"focus-visible:ring-copper-bright focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

			attr_reader :label, :href, :icon

			def initialize(label:, href: "#", icon: "arrow-left-01")
				@label = label
				@href = href
				@icon = icon
			end

			def icon_class = "hgi-stroke hgi-#{icon}"
		end
	end
end
