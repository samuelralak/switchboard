# frozen_string_literal: true

require "test_helper"

module Shared
  module Stepper
    class StepperComponentTest < ViewComponent::TestCase
      def test_renders_all_step_labels
        render_inline(StepperComponent.new(steps: %w[Compose Confirm Track Receive], active: 2))

        assert_text "Compose"
        assert_text "Confirm"
        assert_text "Track"
        assert_text "Receive"
      end

      def test_done_step_is_filled_copper_with_check
        render_inline(StepperComponent.new(steps: %w[Compose Confirm Track], active: 2))

        assert_selector "span.bg-copper.text-canvas", text: "✓"
      end

      def test_current_step_is_outlined_copper_with_number
        render_inline(StepperComponent.new(steps: %w[Compose Confirm Track], active: 2))

        assert_selector "span.border-copper.text-copper", text: "2"
        assert_selector "span.text-ink", text: "Confirm"
      end

      def test_future_step_is_faint_with_number
        render_inline(StepperComponent.new(steps: %w[Compose Confirm Track], active: 2))

        assert_selector "span.border-border-strong.text-ink-faint", text: "3"
      end

      def test_connector_before_active_is_copper_dim_and_others_strong
        render_inline(StepperComponent.new(steps: %w[Compose Confirm Track], active: 2))

        assert_selector "span.h-px.bg-copper-dim"
        assert_selector "span.h-px.bg-border-strong"
      end

      def test_no_connector_after_last_step
        render_inline(StepperComponent.new(steps: %w[Compose Confirm], active: 1))

        assert_selector "span.h-px", count: 1
      end
    end
  end
end
