# frozen_string_literal: true

require "test_helper"

module Shared
  module PriceTag
    class PriceTagComponentTest < ViewComponent::TestCase
      def test_default_renders_delimited_amount_with_suffix
        render_inline(PriceTagComponent.new(amount: 5000))

        assert_selector "span.font-mono.text-base.text-copper.tabular-nums"
        assert_text "5,000"
        assert_text "sat"
      end

      def test_large_size_uses_text_2xl
        render_inline(PriceTagComponent.new(amount: 5000, size: :lg))

        assert_selector "span.text-2xl"
      end

      def test_inline_size_uses_smaller_suffix
        render_inline(PriceTagComponent.new(amount: 250, size: :inline))

        assert_selector "span.text-sm > span.text-ink-faint.text-xs"
      end

      def test_ink_tone
        render_inline(PriceTagComponent.new(amount: 100, tone: :ink))

        assert_selector "span.text-ink"
      end

      def test_custom_suffix
        render_inline(PriceTagComponent.new(amount: 100, suffix: "sats"))

        assert_text "sats"
      end

      def test_unknown_size_and_tone_fall_back_to_defaults
        render_inline(PriceTagComponent.new(amount: 100, size: :huge, tone: :neon))

        assert_selector "span.text-base.text-copper"
      end
    end
  end
end
