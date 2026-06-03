# frozen_string_literal: true

module Shared
	module EmptyState
		# Centered placeholder for empty collections and zero-result states.
		# Renders an icon, title, and body; optional action buttons go in the content slot.
		class EmptyStateComponent < ApplicationComponent
			attr_reader :icon, :title, :body

			def initialize(title:, body:, icon: "unavailable")
				@icon = icon.to_s.presence || "unavailable"
				@title = title
				@body = body
			end
		end
	end
end
