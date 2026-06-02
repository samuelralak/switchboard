# frozen_string_literal: true

module Shared
  module Card
    # A surface panel matching the prototype's card family: a rounded, bordered
    # block on bg-surface used to group catalog tiles, status panels, and detail
    # sections. Padding is a named scale; an optional copper accent border draws
    # attention; interactive cards gain hover affordances and a focus ring and
    # default to a <button>. The chosen tag (:div / :a / :button) wraps the
    # default content slot. Pass href when rendering as a link.
    class CardComponent < ApplicationComponent
      BASE = "rounded-2xl border border-border bg-surface"

      PADDINGS = {
        none: "",
        p4: "p-4",
        p5: "p-5",
        p6: "p-6",
        p7: "p-7"
      }.freeze

      INTERACTIVE = "hover:bg-surface-2 hover:border-border-strong transition-colors " \
                    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright " \
                    "focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

      ACCENTS = { copper: "border-copper-dim" }.freeze

      TAGS = %i[div a button].freeze

      attr_reader :href

      def initialize(padding: :p6, interactive: false, accent: nil, tag: nil, href: nil)
        @padding = PADDINGS.key?(padding.to_s.to_sym) ? padding.to_s.to_sym : :p6
        @interactive = interactive
        @accent = accent&.to_s&.to_sym
        @href = href
        @tag = resolve_tag(tag)
      end

      def card_tag = @tag

      def classes
        tokens = [ BASE, PADDINGS.fetch(@padding) ]
        tokens << INTERACTIVE if @interactive
        tokens << ACCENTS[@accent] if @accent && ACCENTS.key?(@accent)
        tokens.compact_blank.join(" ")
      end

      private

      def resolve_tag(tag)
        candidate = tag.nil? ? default_tag : tag.to_s.to_sym
        TAGS.include?(candidate) ? candidate : default_tag
      end

      def default_tag = @interactive ? :button : :div
    end
  end
end
