# frozen_string_literal: true

module Shared
  module Icon
    # Renders a Hugeicons stroke glyph as an inline <i> element. The icon name maps
    # to its hgi class (e.g. "shield-01" => hgi-shield-01). Size maps to a Tailwind
    # text-* class via the frozen SIZES hash; color is passed through verbatim as a
    # full class (e.g. "text-copper"). Decorative by default (aria-hidden).
    class IconComponent < ApplicationComponent
      SIZES = {
        xs: "text-xs",
        sm: "text-sm",
        base: "text-base",
        lg: "text-lg",
        xl: "text-xl",
        xxl: "text-2xl"
      }.freeze

      def initialize(name:, size: nil, color: nil, extra: nil)
        @name = name
        @size = size
        @color = color
        @extra = extra
      end

      def icon_class = "hgi-#{@name}"
      def size_class = @size && SIZES[@size.to_s.to_sym]

      def classes
        [ "hgi-stroke", icon_class, size_class, @color, @extra ].compact.join(" ")
      end
    end
  end
end
