# frozen_string_literal: true

module Shared
	module Badge
		class TypeBadgeComponentPreview < ViewComponent::Preview
			def dark
				render(TypeBadgeComponent.new(type: "D"))
			end

			def live
				render(TypeBadgeComponent.new(type: "L"))
			end

			def combined
				render(TypeBadgeComponent.new(type: "D·L"))
			end
		end
	end
end
