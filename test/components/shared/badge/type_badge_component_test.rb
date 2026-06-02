# frozen_string_literal: true

require "test_helper"

module Shared
  module Badge
    class TypeBadgeComponentTest < ViewComponent::TestCase
      def test_renders_type_text_in_mono
        render_inline(TypeBadgeComponent.new(type: "D"))

        assert_selector "span.font-mono.text-xs"
        assert_text "D"
      end

      def test_type_with_l_glows_copper
        render_inline(TypeBadgeComponent.new(type: "L"))

        assert_selector "span.text-copper"
        assert_text "L"
      end

      def test_type_without_l_is_faint
        render_inline(TypeBadgeComponent.new(type: "D"))

        assert_selector "span.text-ink-faint"
      end

      def test_combined_type_containing_l_glows_copper
        render_inline(TypeBadgeComponent.new(type: "D·L"))

        assert_selector "span.text-copper"
        assert_text "D·L"
      end
    end
  end
end
