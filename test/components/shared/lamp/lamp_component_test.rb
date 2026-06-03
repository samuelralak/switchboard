# frozen_string_literal: true

require "test_helper"

module Shared
	module Lamp
		class LampComponentTest < ViewComponent::TestCase
			def test_current_status_pulses_with_live_fill
				render_inline(LampComponent.new(status: :current))

				assert_selector "span.bg-lamp-live.animate-pulse.shadow-lamp[aria-hidden='true']"
			end

			def test_done_status_is_solid_copper
				render_inline(LampComponent.new(status: :done))

				assert_selector "span.bg-copper.rounded-full"
			end

			def test_settled_status_uses_settled_fill
				render_inline(LampComponent.new(status: :settled))

				assert_selector "span.bg-lamp-settled"
			end

			def test_fault_status_uses_fault_fill
				render_inline(LampComponent.new(status: :fault))

				assert_selector "span.bg-lamp-fault"
			end

			def test_future_status_is_a_hollow_ring
				render_inline(LampComponent.new(status: :future))

				assert_selector "span.border.border-border-strong"
			end

			def test_unknown_status_falls_back_to_future
				render_inline(LampComponent.new(status: :nope))

				assert_selector "span.border.border-border-strong"
			end
		end
	end
end
