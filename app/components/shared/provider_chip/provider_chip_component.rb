# frozen_string_literal: true

module Shared
	module ProviderChip
		# Compact inline identity chip: identicon avatar (seeded from the npub) with
		# the provider's display name and a truncated npub.
		class ProviderChipComponent < ApplicationComponent
			attr_reader :name, :npub, :size

			# linked: render as a link to the identity's profile. Only valid where the chip is NOT nested in
			# another interactive element (a detail drawer, never a card button).
			def initialize(name:, npub:, size: 20, linked: false)
				@name = name
				@npub = npub.to_s
				@size = size
				@linked = linked
			end

			def linked? = @linked

			def short_npub = @npub[0, 9]
		end
	end
end
