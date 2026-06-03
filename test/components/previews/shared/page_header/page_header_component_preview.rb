# frozen_string_literal: true

module Shared
	module PageHeader
		class PageHeaderComponentPreview < ViewComponent::Preview
			def full
				render(PageHeaderComponent.new(
								eyebrow: "ledger",
								title: "My requests",
								subtitle: "Every request is one workflow instance."
							))
			end

			def title_only
				render(PageHeaderComponent.new(title: "Settings"))
			end

			def medium_spacing
				render(PageHeaderComponent.new(
								title: "Open disputes",
								subtitle: "Funds stay escrowed until resolution.",
								spacing: :md
							))
			end
		end
	end
end
