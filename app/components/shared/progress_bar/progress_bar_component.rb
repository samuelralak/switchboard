# frozen_string_literal: true

module Shared
	module ProgressBar
		# A copper progress track. +value+ is a 0..1 Float or 0..100 Integer,
		# clamped to 0..100 pct. +show_value+ adds a "%.2f" readout of the fraction.
		class ProgressBarComponent < ApplicationComponent
			def initialize(value: 0, show_value: false)
				@fraction = normalize(value)
				@show_value = show_value
			end

			def pct = (@fraction * 100).round

			def readout = format("%.2f", @fraction)

			def show_value? = @show_value

			private

			def normalize(value)
				fraction = value.is_a?(Integer) ? value / 100.0 : value.to_f
				fraction.clamp(0.0, 1.0)
			end
		end
	end
end
