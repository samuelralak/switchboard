# frozen_string_literal: true

require "test_helper"

module Shared
	module AttestationBadge
		class AttestationBadgeComponentTest < ViewComponent::TestCase
			def test_renders_nothing_when_not_attested
				render_inline(AttestationBadgeComponent.new(attested: false))

				assert_no_selector "i.hgi-security-check"
			end

			def test_renders_the_shield_and_label_when_attested
				render_inline(AttestationBadgeComponent.new(attested: true))

				assert_selector "i.hgi-security-check"
				assert_selector "span.sr-only", text: "Listed on Switchboard"
				assert_selector "span[aria-hidden='true']", text: "Listed on Switchboard"
			end

			def test_custom_label
				render_inline(AttestationBadgeComponent.new(attested: true, label: "Posted on Switchboard"))

				assert_selector "span.sr-only", text: "Posted on Switchboard"
			end

			def test_is_not_a_tab_stop_by_default
				render_inline(AttestationBadgeComponent.new(attested: true))

				assert_no_selector "span[tabindex]"
			end

			def test_focusable_adds_a_tab_stop_and_focus_ring
				render_inline(AttestationBadgeComponent.new(attested: true, focusable: true))

				assert_selector "span[tabindex='0'].focus-visible\\:ring-2"
			end
		end
	end
end
