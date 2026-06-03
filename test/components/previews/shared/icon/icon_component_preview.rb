# frozen_string_literal: true

module Shared
	module Icon
		class IconComponentPreview < ViewComponent::Preview
			def default
				render(IconComponent.new(name: "shield-01"))
			end

			def with_size_and_color
				render(IconComponent.new(name: "shield-01", size: :lg, color: "text-copper"))
			end

			def extra_large
				render(IconComponent.new(name: "checkmark-circle-02", size: :xxl, color: "text-lamp-settled"))
			end

			def with_extra_classes
				render(IconComponent.new(name: "alert-02", size: :sm, color: "text-lamp-fault", extra: "animate-pulse"))
			end
		end
	end
end
