# frozen_string_literal: true

module Shared
	module Eyebrow
		class EyebrowComponentPreview < ViewComponent::Preview
			def default
				render(EyebrowComponent.new.with_content("reference service"))
			end

			def with_margin
				render(EyebrowComponent.new(margin: "mb-2.5").with_content("how it works"))
			end
		end
	end
end
