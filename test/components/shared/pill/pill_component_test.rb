# frozen_string_literal: true

require "test_helper"

module Shared
  module Pill
    class PillComponentTest < ViewComponent::TestCase
      def test_copper_variant_is_default
        render_inline(PillComponent.new.with_content("LOCKED 120 sat"))

        assert_selector "span.border-copper-dim.bg-copper\\/10.px-2.py-0\\.5.font-mono.text-xs.text-copper"
        assert_selector "span.h-1\\.5.w-1\\.5.rounded-full.bg-copper"
        assert_text "LOCKED 120 sat"
      end

      def test_surface_variant_uses_neutral_chrome_and_tone
        render_inline(PillComponent.new(variant: :surface, tone: :live).with_content("LIVE"))

        assert_selector "span.border-border.bg-surface.px-2\\.5.py-1.text-lamp-live"
        assert_selector "span.rounded-full.bg-lamp-live"
        assert_text "LIVE"
      end

      def test_label_keyword_renders_without_content_block
        render_inline(PillComponent.new(label: "120 sat"))

        assert_text "120 sat"
      end

      def test_dot_can_be_hidden
        render_inline(PillComponent.new(dot: false).with_content("120 sat"))

        assert_no_selector "span.rounded-full"
        assert_text "120 sat"
      end

      def test_unknown_variant_falls_back_to_copper
        render_inline(PillComponent.new(variant: :nope).with_content("x"))

        assert_selector "span.border-copper-dim.text-copper"
      end

      def test_unknown_tone_on_surface_falls_back_to_copper
        render_inline(PillComponent.new(variant: :surface, tone: :nope).with_content("x"))

        assert_selector "span.border-border.text-copper"
        assert_selector "span.rounded-full.bg-copper"
      end
    end
  end
end
