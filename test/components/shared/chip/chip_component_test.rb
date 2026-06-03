# frozen_string_literal: true

require "test_helper"

module Shared
	module Chip
		class ChipComponentTest < ViewComponent::TestCase
			def test_renders_label_with_tone_text_and_dot
				render_inline(ChipComponent.new(tone: :settled, label: "completed"))

				assert_selector "span.text-lamp-settled.font-mono.text-xs"
				assert_selector "span.rounded-full.bg-lamp-settled"
				assert_text "completed"
			end

			def test_copper_tone_classes
				render_inline(ChipComponent.new(tone: :copper, label: "claimed"))

				assert_selector "span.text-copper"
				assert_selector "span.bg-copper"
				assert_text "claimed"
			end

			def test_content_slot_used_when_no_label
				render_inline(ChipComponent.new(tone: :live).with_content("open"))

				assert_selector "span.text-lamp-live"
				assert_text "open"
			end

			def test_dot_false_omits_dot_span
				render_inline(ChipComponent.new(tone: :live, label: "online", dot: false))

				assert_text "online"
				assert_no_selector "span.rounded-full"
			end

			def test_faint_tone_has_nil_dot_so_no_dot_span
				render_inline(ChipComponent.new(tone: :faint, label: "12 sats"))

				assert_selector "span.text-ink-faint"
				assert_no_selector "span.rounded-full"
				assert_text "12 sats"
			end

			def test_bordered_adds_surface_classes
				render_inline(ChipComponent.new(tone: :copper, label: "escrow", bordered: true))

				assert_selector "span.rounded-md.border.border-border.bg-surface.px-2\\.5.py-1"
				assert_text "escrow"
			end

			def test_unknown_tone_falls_back_to_muted
				render_inline(ChipComponent.new(tone: :nope, label: "x"))

				assert_selector "span.text-ink-muted"
				assert_selector "span.bg-ink-faint"
			end
		end
	end
end
