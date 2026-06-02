# frozen_string_literal: true

require "test_helper"

module Shared
  module Icon
    class IconComponentTest < ViewComponent::TestCase
      def test_renders_stroke_and_named_icon
        render_inline(IconComponent.new(name: "shield-01"))

        assert_selector "i.hgi-stroke.hgi-shield-01"
        assert_selector "i[aria-hidden='true']"
      end

      def test_maps_size_to_text_class
        render_inline(IconComponent.new(name: "shield-01", size: :lg))

        assert_selector "i.hgi-shield-01.text-lg"
      end

      def test_applies_color_class
        render_inline(IconComponent.new(name: "shield-01", color: "text-copper"))

        assert_selector "i.hgi-shield-01.text-copper"
      end

      def test_applies_extra_classes
        render_inline(IconComponent.new(name: "alert-02", extra: "animate-pulse"))

        assert_selector "i.hgi-alert-02.animate-pulse"
      end

      def test_unknown_size_is_omitted
        render_inline(IconComponent.new(name: "shield-01", size: :huge))

        assert_selector "i.hgi-stroke.hgi-shield-01"
        assert_no_selector "i[class*='text-']"
      end
    end
  end
end
