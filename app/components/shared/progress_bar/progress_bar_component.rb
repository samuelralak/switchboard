# frozen_string_literal: true

module Shared
  module ProgressBar
    # A thin copper progress track for ratings, completion, and reputation meters,
    # matching the prototype. Accepts the value as either a 0..1 fraction (Float)
    # or a 0..100 percentage (Integer); both normalize and clamp to a 0..100 pct
    # used for the inline track width. With +show_value+ the 0..1 fraction renders
    # as a "%.2f" mono readout (e.g. 0.94) beside the track.
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
