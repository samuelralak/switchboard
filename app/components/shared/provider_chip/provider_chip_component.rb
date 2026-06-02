# frozen_string_literal: true

module Shared
  module ProviderChip
    # A compact inline identity chip: a small identicon avatar (seeded from the
    # npub) next to the provider's display name and a truncated npub. Used in
    # lists, tables, and cards where a full identity menu would be too heavy.
    class ProviderChipComponent < ApplicationComponent
      attr_reader :name, :npub, :size

      def initialize(name:, npub:, size: 20)
        @name = name
        @npub = npub.to_s
        @size = size
      end

      def short_npub = @npub[0, 9]
    end
  end
end
