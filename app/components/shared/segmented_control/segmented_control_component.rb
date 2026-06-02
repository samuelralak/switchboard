# frozen_string_literal: true

module Shared
  module SegmentedControl
    # A horizontal group of mutually exclusive links, styled as a segmented
    # control. Each segment is a hash with :label, :value, and :href; the segment
    # whose :value matches the +active+ prop is rendered in the selected state.
    # Used for filtering catalog views (for example All / Automated) where each
    # option is a distinct URL.
    class SegmentedControlComponent < ApplicationComponent
      FOCUS = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright " \
              "focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

      SEGMENT_BASE = "inline-flex items-center h-8 px-3.5 rounded-md text-sm font-medium transition-colors"

      ACTIVE_CLASS = "bg-surface-2 text-ink"
      INACTIVE_CLASS = "text-ink-muted hover:text-ink"

      attr_reader :segments

      def initialize(segments: [], active: nil)
        @segments = Array(segments)
        @active = active
      end

      def active?(segment) = segment[:value] == @active

      def segment_class(segment)
        state = active?(segment) ? ACTIVE_CLASS : INACTIVE_CLASS
        "#{SEGMENT_BASE} #{FOCUS} #{state}"
      end

      def aria_attrs(segment) = active?(segment) ? { current: "page" } : {}
    end
  end
end
