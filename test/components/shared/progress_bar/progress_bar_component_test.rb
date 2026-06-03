# frozen_string_literal: true

require "test_helper"

module Shared
	module ProgressBar
		class ProgressBarComponentTest < ViewComponent::TestCase
			def test_fraction_sets_track_width_and_readout
				render_inline(ProgressBarComponent.new(value: 0.94, show_value: true))

				assert_selector "div.bg-copper[style='width: 94%']"
				assert_selector "span.font-mono.tabular-nums"
				assert_text "0.94"
			end

			def test_integer_percentage_normalizes_to_width
				render_inline(ProgressBarComponent.new(value: 72))

				assert_selector "div.bg-copper[style='width: 72%']"
			end

			def test_value_hidden_by_default
				render_inline(ProgressBarComponent.new(value: 0.5))

				assert_selector "div.bg-inset.overflow-hidden"
				assert_no_selector "span.font-mono"
			end

			def test_clamps_above_full
				render_inline(ProgressBarComponent.new(value: 1.5, show_value: true))

				assert_selector "div.bg-copper[style='width: 100%']"
				assert_text "1.00"
			end

			def test_clamps_below_zero
				render_inline(ProgressBarComponent.new(value: -0.4, show_value: true))

				assert_selector "div.bg-copper[style='width: 0%']"
				assert_text "0.00"
			end
		end
	end
end
