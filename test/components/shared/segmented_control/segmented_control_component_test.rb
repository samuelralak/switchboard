# frozen_string_literal: true

require "test_helper"

module Shared
	module SegmentedControl
		class SegmentedControlComponentTest < ViewComponent::TestCase
			def segments
				[
					{ label: "All",       value: "all",       href: "/catalog" },
					{ label: "Automated", value: "automated", href: "/catalog/automated" }
				]
			end

			def test_renders_track_with_each_segment_label
				render_inline(SegmentedControlComponent.new(segments: segments, active: "all"))

				assert_selector "div.inline-flex.rounded-lg.border.bg-surface a", count: 2
				assert_text "All"
				assert_text "Automated"
			end

			def test_active_segment_gets_selected_classes
				render_inline(SegmentedControlComponent.new(segments: segments, active: "all"))

				assert_selector "a.bg-surface-2.text-ink", text: "All"
				assert_selector "a[aria-current='page']", text: "All"
			end

			def test_inactive_segment_gets_muted_classes
				render_inline(SegmentedControlComponent.new(segments: segments, active: "all"))

				assert_selector "a.text-ink-muted", text: "Automated"
			end

			def test_segment_links_to_its_href
				render_inline(SegmentedControlComponent.new(segments: segments, active: "all"))

				assert_selector "a[href='/catalog/automated']", text: "Automated"
			end

			def test_unknown_active_marks_no_segment_current
				render_inline(SegmentedControlComponent.new(segments: segments, active: "nope"))

				assert_no_selector "a[aria-current='page']"
			end

			def test_empty_segments_renders_empty_track
				render_inline(SegmentedControlComponent.new(segments: [], active: nil))

				assert_selector "div.inline-flex.bg-surface"
				assert_no_selector "a"
			end
		end
	end
end
