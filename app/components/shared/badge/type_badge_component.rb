# frozen_string_literal: true

module Shared
  module Badge
    # A compact monospace tag marking a workflow node's type, matching the
    # prototype's typeBadge: nodes that involve an LLM (the type string contains
    # "L", e.g. "L" or "D·L") are tinted copper; purely deterministic nodes
    # ("D") render faint. The type string is passed verbatim.
    class TypeBadgeComponent < ApplicationComponent
      attr_reader :type

      def initialize(type:)
        @type = type.to_s
      end

      def color_class = type.include?("L") ? "text-copper" : "text-ink-faint"
    end
  end
end
