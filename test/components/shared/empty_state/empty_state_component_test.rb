# frozen_string_literal: true

require "test_helper"

module Shared
  module EmptyState
    class EmptyStateComponentTest < ViewComponent::TestCase
      def test_renders_title_and_body
        render_inline(EmptyStateComponent.new(title: "No service for that yet.",
                                              body: "Nothing in the catalog matches."))

        assert_text "No service for that yet."
        assert_text "Nothing in the catalog matches."
      end

      def test_default_icon_is_unavailable
        render_inline(EmptyStateComponent.new(title: "Empty", body: "Nothing here"))

        assert_selector "i.hgi-stroke.hgi-unavailable.text-ink-faint"
      end

      def test_custom_icon
        render_inline(EmptyStateComponent.new(icon: "search-01", title: "No results", body: "Try again"))

        assert_selector "i.hgi-search-01"
      end

      def test_blank_icon_falls_back_to_unavailable
        render_inline(EmptyStateComponent.new(icon: "", title: "Empty", body: "Nothing here"))

        assert_selector "i.hgi-unavailable"
      end

      def test_omits_action_row_without_content
        render_inline(EmptyStateComponent.new(title: "Empty", body: "Nothing here"))

        assert_no_selector "div.flex.justify-center"
      end

      def test_renders_action_row_with_content
        render_inline(EmptyStateComponent.new(title: "Empty", body: "Nothing here").with_content("Add one"))

        assert_selector "div.flex.gap-2\\.5.justify-center.flex-wrap"
        assert_text "Add one"
      end
    end
  end
end
