# frozen_string_literal: true

module Shared
	module Badge
		# Renders a workflow node's type string verbatim. A type containing "L"
		# (LLM-involved, e.g. "L" or "D·L") is copper; otherwise faint ("D").
		class TypeBadgeComponent < ApplicationComponent
			attr_reader :type

			def initialize(type:)
				@type = type.to_s
			end

			def color_class = type.include?("L") ? "text-copper" : "text-ink-faint"
		end
	end
end
