# frozen_string_literal: true

require "test_helper"

module Shared
  module Chip
    class StateChipComponentTest < ViewComponent::TestCase
      def test_completed_maps_to_settled_tone
        render_inline(StateChipComponent.new(state: :completed))

        assert_selector "span.text-lamp-settled.font-mono"
        assert_selector "span.bg-lamp-settled"
        assert_text "completed"
      end

      def test_open_maps_to_live_tone
        render_inline(StateChipComponent.new(state: :open))

        assert_selector "span.text-lamp-live"
        assert_text "open"
      end

      def test_claimed_maps_to_copper_tone_with_short_label
        render_inline(StateChipComponent.new(state: :claimed))

        assert_selector "span.text-copper"
        assert_text "claimed"
      end

      def test_verifying_delivery_uses_short_label
        render_inline(StateChipComponent.new(state: :verifying_delivery))

        assert_selector "span.text-copper"
        assert_text "verifying"
      end

      def test_failed_maps_to_fault_tone
        render_inline(StateChipComponent.new(state: :failed))

        assert_selector "span.text-lamp-fault"
        assert_text "failed"
      end

      def test_string_state_is_normalized
        render_inline(StateChipComponent.new(state: "completed"))

        assert_selector "span.text-lamp-settled"
        assert_text "completed"
      end

      def test_unknown_state_falls_back_to_neutral_with_raw_label
        render_inline(StateChipComponent.new(state: :archived))

        assert_selector "span.text-ink-muted"
        assert_selector "span.bg-ink-muted"
        assert_text "archived"
      end
    end
  end
end
