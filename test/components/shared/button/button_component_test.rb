# frozen_string_literal: true

require "test_helper"

module Shared
  module Button
    class ButtonComponentTest < ViewComponent::TestCase
      def test_primary_variant_renders_button_with_fill_classes
        render_inline(ButtonComponent.new(variant: :primary).with_content("Publish"))

        assert_selector "button.bg-copper.text-canvas[type='button']"
        assert_text "Publish"
      end

      def test_ghost_variant_renders_border_classes
        render_inline(ButtonComponent.new(variant: :ghost).with_content("Cancel"))

        assert_selector "button.border.text-ink-secondary"
        assert_text "Cancel"
      end

      def test_leading_and_trailing_icons_render
        render_inline(ButtonComponent.new(icon: "rocket-01", trailing_icon: "arrow-right-01").with_content("Go"))

        assert_selector "button i.hgi-stroke.hgi-rocket-01"
        assert_selector "button i.hgi-stroke.hgi-arrow-right-01"
      end

      def test_size_applies_height_class
        render_inline(ButtonComponent.new(size: :lg).with_content("Big"))

        assert_selector "button.h-12.px-5"
      end

      def test_full_appends_width_class
        render_inline(ButtonComponent.new(full: true).with_content("Wide"))

        assert_selector "button.w-full"
      end

      def test_link_tag_renders_anchor_with_href
        render_inline(ButtonComponent.new(tag: :a, href: "/listings").with_content("Browse"))

        assert_selector "a[href='/listings']"
        assert_text "Browse"
      end

      def test_disabled_button_sets_attribute
        render_inline(ButtonComponent.new(disabled: true).with_content("Wait"))

        assert_selector "button[disabled]"
      end

      def test_unknown_variant_falls_back_to_primary
        render_inline(ButtonComponent.new(variant: :nope).with_content("x"))

        assert_selector "button.bg-copper"
      end
    end
  end
end
