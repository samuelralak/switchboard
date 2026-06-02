# frozen_string_literal: true

require "test_helper"

module Shared
  module Card
    class CardComponentTest < ViewComponent::TestCase
      def test_default_renders_div_with_base_and_p6
        render_inline(CardComponent.new.with_content("Body"))

        assert_selector "div.rounded-2xl.border.border-border.bg-surface.p-6"
        assert_text "Body"
      end

      def test_padding_maps_to_literal_class
        render_inline(CardComponent.new(padding: :p5).with_content("Compact"))

        assert_selector "div.p-5"
        assert_text "Compact"
      end

      def test_padding_none_emits_no_padding_class
        render_inline(CardComponent.new(padding: :none).with_content("Flush"))

        assert_selector "div.rounded-2xl"
        assert_no_selector "div.p-6"
      end

      def test_interactive_defaults_to_button_with_hover_and_focus
        render_inline(CardComponent.new(interactive: true).with_content("Press"))

        assert_selector "button.transition-colors[type='button']"
        assert_selector "button[class*='hover:bg-surface-2']"
        assert_selector "button[class*='focus-visible:ring-copper-bright']"
        assert_text "Press"
      end

      def test_copper_accent_appends_border_class
        render_inline(CardComponent.new(accent: :copper).with_content("Accent"))

        assert_selector "div.border-copper-dim"
      end

      def test_link_tag_renders_anchor_with_href
        render_inline(CardComponent.new(tag: :a, href: "/listings/1").with_content("Open"))

        assert_selector "a[href='/listings/1']"
        assert_text "Open"
      end

      def test_unknown_padding_falls_back_to_p6
        render_inline(CardComponent.new(padding: :nope).with_content("x"))

        assert_selector "div.p-6"
      end

      def test_unknown_tag_falls_back_to_div
        render_inline(CardComponent.new(tag: :section).with_content("x"))

        assert_selector "div.rounded-2xl"
      end
    end
  end
end
