# frozen_string_literal: true

module Shared
	module EmptyState
		class EmptyStateComponentPreview < ViewComponent::Preview
			def default
				render(EmptyStateComponent.new(
								title: "No service for that yet.",
								body: "Nothing in the catalog matches."
							))
			end

			def with_custom_icon
				render(EmptyStateComponent.new(
								icon: "search-01",
								title: "No results found.",
								body: "Try a different search term or broaden your filters."
							))
			end

			def with_actions
				render(EmptyStateComponent.new(
					title: "No service for that yet.",
					body: "Nothing in the catalog matches your request."
				).with_content(tag.button("Request a service", class: "text-sm text-copper-bright")))
			end
		end
	end
end
