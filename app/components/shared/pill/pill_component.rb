# frozen_string_literal: true

module Shared
  module Pill
    # A small inline status pill with a leading dot, matching the prototype's
    # mono-cased metadata tags (e.g. "LOCKED 120 sat"). Two visual variants:
    #   :copper  (default) the accent pill: copper border, tinted fill, copper text/dot.
    #   :surface a neutral surface pill whose text/dot color comes from a tone.
    # For the :surface variant the tone tints the text and dot, reusing the same
    # literal tone map as Chip (copper/live/settled/fault/muted; default copper).
    # Pass the label as block content (or via the :label keyword). The leading dot
    # is shown by default and can be hidden with dot: false.
    class PillComponent < ApplicationComponent
      VARIANTS = {
        copper: {
          border: "border-copper-dim", bg: "bg-copper/10", pad: "px-2 py-0.5"
        },
        surface: {
          border: "border-border", bg: "bg-surface", pad: "px-2.5 py-1"
        }
      }.freeze

      TONES = {
        copper: { text: "text-copper", dot: "bg-copper" },
        live: { text: "text-lamp-live", dot: "bg-lamp-live" },
        settled: { text: "text-lamp-settled", dot: "bg-lamp-settled" },
        fault: { text: "text-lamp-fault", dot: "bg-lamp-fault" },
        muted: { text: "text-ink-muted", dot: "bg-ink-muted" }
      }.freeze

      attr_reader :label

      def initialize(variant: :copper, tone: :copper, label: nil, dot: true)
        @variant = VARIANTS.key?(variant.to_s.to_sym) ? variant.to_s.to_sym : :copper
        @tone = TONES.key?(tone.to_s.to_sym) ? tone.to_s.to_sym : :copper
        @label = label
        @dot = dot
      end

      def dot? = @dot

      def border_class = VARIANTS.fetch(@variant)[:border]
      def bg_class = VARIANTS.fetch(@variant)[:bg]
      def pad_class = VARIANTS.fetch(@variant)[:pad]

      # The :copper variant is always copper-toned; :surface defers to the tone.
      def text_class = @variant == :copper ? TONES.fetch(:copper)[:text] : TONES.fetch(@tone)[:text]
      def dot_class = @variant == :copper ? TONES.fetch(:copper)[:dot] : TONES.fetch(@tone)[:dot]
    end
  end
end
