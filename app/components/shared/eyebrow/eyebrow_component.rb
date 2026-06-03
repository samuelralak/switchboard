# frozen_string_literal: true

module Shared
	module Eyebrow
		# Renders an uppercase eyebrow label from the default content slot.
		# +margin+: optional margin utility class.
		class EyebrowComponent < ApplicationComponent
			attr_reader :margin

			def initialize(margin: nil)
				@margin = margin
			end
		end
	end
end
