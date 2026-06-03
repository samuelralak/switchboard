# frozen_string_literal: true

module Shared
	module PriceTag
		class PriceTagComponentPreview < ViewComponent::Preview
			def small
				render(PriceTagComponent.new(amount: 5000))
			end

			def large
				render(PriceTagComponent.new(amount: 5000, size: :lg))
			end

			def inline
				render(PriceTagComponent.new(amount: 250, size: :inline))
			end

			def ink_tone
				render(PriceTagComponent.new(amount: 1_250_000, tone: :ink))
			end

			def custom_suffix
				render(PriceTagComponent.new(amount: 21_000_000, suffix: "sats"))
			end
		end
	end
end
