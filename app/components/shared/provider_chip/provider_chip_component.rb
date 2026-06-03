# frozen_string_literal: true

module Shared
	module ProviderChip
		# Compact inline identity chip: identicon avatar (seeded from the npub) with
		# the provider's display name and a truncated npub.
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
