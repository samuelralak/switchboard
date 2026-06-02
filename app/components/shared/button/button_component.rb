# frozen_string_literal: true

module Shared
  module Button
    # The prototype's button family: a copper-filled primary action and a quiet
    # ghost variant, rendered as a <button> or an <a>. The variant picks the fill
    # and hover treatment; the size picks the height and horizontal padding.
    # Optional leading / trailing Hugeicon names bracket the label (the block
    # content). Pass tag: :a with an href: to render a link styled as a button.
    class ButtonComponent < ApplicationComponent
      FOCUS = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright " \
              "focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

      BASE = "inline-flex items-center justify-center gap-2 rounded-lg font-medium transition-colors " \
             "#{FOCUS} disabled:opacity-40 disabled:pointer-events-none".freeze

      VARIANTS = {
        primary: "bg-copper text-canvas hover:bg-copper-bright active:translate-y-px",
        ghost: "border border-border text-ink-secondary hover:text-ink hover:border-border-strong hover:bg-surface"
      }.freeze

      SIZES = {
        xs: "h-7 px-3",
        sm: "h-8 px-3 text-sm",
        md: "h-10 px-4",
        lg: "h-12 px-5"
      }.freeze

      def initialize(variant: :primary, size: :md, tag: :button, href: nil, # rubocop:disable Metrics/ParameterLists
                     type: "button", disabled: false, full: false, icon: nil, trailing_icon: nil)
        @variant = VARIANTS.key?(variant.to_s.to_sym) ? variant.to_s.to_sym : :primary
        @size = SIZES.key?(size.to_s.to_sym) ? size.to_s.to_sym : :md
        @tag = tag.to_s == "a" ? :a : :button
        @href = href
        @type = type
        @disabled = disabled
        @full = full
        @leading_icon = icon
        @trailing_icon = trailing_icon
      end

      def link? = @tag == :a

      def classes
        [ BASE, VARIANTS.fetch(@variant), SIZES.fetch(@size), (@full ? "w-full" : nil) ].compact.join(" ")
      end

      def html_attributes
        if link?
          { href: @href }
        else
          { type: @type, disabled: @disabled }
        end
      end

      attr_reader :leading_icon, :trailing_icon
    end
  end
end
