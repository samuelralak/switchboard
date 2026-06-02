# frozen_string_literal: true

require "test_helper"

module Shared
  module BackLink
    class BackLinkComponentTest < ViewComponent::TestCase
      def test_renders_label_and_href
        render_inline(BackLinkComponent.new(label: "catalog", href: "/catalog"))

        assert_selector "a[href='/catalog']"
        assert_text "catalog"
      end

      def test_default_icon_is_left_arrow
        render_inline(BackLinkComponent.new(label: "catalog"))

        assert_selector "a i.hgi-stroke.hgi-arrow-left-01[aria-hidden='true']"
      end

      def test_default_href_is_hash
        render_inline(BackLinkComponent.new(label: "catalog"))

        assert_selector "a[href='#']"
      end

      def test_custom_icon
        render_inline(BackLinkComponent.new(label: "back", icon: "arrow-left-02"))

        assert_selector "i.hgi-arrow-left-02"
      end

      def test_has_mono_and_transition_classes
        render_inline(BackLinkComponent.new(label: "catalog"))

        assert_selector "a.font-mono.text-xs.text-ink-muted.transition-colors"
      end
    end
  end
end
