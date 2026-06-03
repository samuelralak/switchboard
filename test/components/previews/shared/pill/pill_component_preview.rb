# frozen_string_literal: true

module Shared
	module Pill
		class PillComponentPreview < ViewComponent::Preview
			def copper
				render(PillComponent.new.with_content("LOCKED 120 sat"))
			end

			def surface_live
				render(PillComponent.new(variant: :surface, tone: :live).with_content("LIVE"))
			end

			def surface_settled
				render(PillComponent.new(variant: :surface, tone: :settled).with_content("SETTLED"))
			end

			def surface_fault
				render(PillComponent.new(variant: :surface, tone: :fault).with_content("FAULT"))
			end

			def surface_muted
				render(PillComponent.new(variant: :surface, tone: :muted).with_content("DRAFT"))
			end

			def without_dot
				render(PillComponent.new(dot: false).with_content("120 sat"))
			end

			def with_label
				render(PillComponent.new(label: "LOCKED 120 sat"))
			end
		end
	end
end
