# frozen_string_literal: true

module Shared
  module Eyebrow
    # A small uppercase, copper-tinted label that sits above a heading or section,
    # matching the prototype's eyebrow treatment (mono, tight letterforms, wide
    # tracking). The label text comes from the default content slot. Pass an
    # optional full margin utility (e.g. "mb-2.5") to space it from what follows.
    class EyebrowComponent < ApplicationComponent
      attr_reader :margin

      def initialize(margin: nil)
        @margin = margin
      end
    end
  end
end
