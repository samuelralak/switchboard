# frozen_string_literal: true

require "test_helper"

module Shared
	module PageHeader
		class PageHeaderComponentTest < ViewComponent::TestCase
			def test_renders_title_in_display_heading
				render_inline(PageHeaderComponent.new(title: "My requests"))

				assert_selector "h1.font-display.font-semibold.text-ink", text: "My requests"
			end

			def test_default_spacing_uses_header_wrapper
				render_inline(PageHeaderComponent.new(title: "My requests"))

				assert_selector "header.mb-9"
			end

			def test_medium_spacing_uses_div_wrapper
				render_inline(PageHeaderComponent.new(title: "Open disputes", spacing: :md))

				assert_selector "div.mb-6"
				assert_no_selector "header"
			end

			def test_eyebrow_renders_when_present
				render_inline(PageHeaderComponent.new(eyebrow: "ledger", title: "My requests"))

				assert_selector "p.font-medium.uppercase.text-copper", text: "ledger"
			end

			def test_eyebrow_omitted_when_absent
				render_inline(PageHeaderComponent.new(title: "My requests"))

				assert_no_selector "p.text-copper"
			end

			def test_subtitle_renders_when_present
				render_inline(PageHeaderComponent.new(title: "My requests", subtitle: "One workflow instance."))

				assert_selector "p.text-ink-muted.max-w-2xl", text: "One workflow instance."
			end

			def test_unknown_spacing_falls_back_to_lg
				render_inline(PageHeaderComponent.new(title: "My requests", spacing: :nope))

				assert_selector "header.mb-9"
			end
		end
	end
end
