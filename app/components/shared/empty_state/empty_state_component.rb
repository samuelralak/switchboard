# frozen_string_literal: true

module Shared
  module EmptyState
    # A centered placeholder for empty collections and zero-result states, matching
    # the prototype's empty-state card. Renders a muted Hugeicon, a title lead, and
    # a supporting body line. Optional action buttons go in the default content slot;
    # the action row is omitted entirely when no content is given.
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
