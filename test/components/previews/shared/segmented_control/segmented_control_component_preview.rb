# frozen_string_literal: true

module Shared
	module SegmentedControl
		class SegmentedControlComponentPreview < ViewComponent::Preview
			def default
				render(SegmentedControlComponent.new(segments: filter_segments, active: "all"))
			end

			def second_active
				render(SegmentedControlComponent.new(segments: filter_segments, active: "automated"))
			end

			def three_segments
				segments = [
					{ label: "All",       value: "all",       href: "#" },
					{ label: "Automated", value: "automated", href: "#" },
					{ label: "Manual",    value: "manual",    href: "#" }
				]
				render(SegmentedControlComponent.new(segments: segments, active: "manual"))
			end

			private

			def filter_segments
				[
					{ label: "All",       value: "all",       href: "#" },
					{ label: "Automated", value: "automated", href: "#" }
				]
			end
		end
	end
end
