# frozen_string_literal: true

require "test_helper"

module Shared
  module Alert
    class AlertComponentTest < ViewComponent::TestCase
      def test_error_tone_has_role_and_alert_icon
        render_inline(AlertComponent.new(tone: :error).with_content("Something went wrong"))

        assert_selector "[role='alert'] i.hgi-alert-02"
        assert_text "Something went wrong"
      end

      def test_info_tone_renders_title_as_lead
        render_inline(AlertComponent.new(tone: :info, title: "Escrowed").with_content("Every job"))

        assert_selector "i.hgi-shield-01"
        assert_text "Escrowed"
        assert_text "Every job"
      end

      def test_success_tone_icon
        render_inline(AlertComponent.new(tone: :success).with_content("Published"))

        assert_selector "i.hgi-checkmark-circle-02"
      end

      def test_for_flash_maps_alert_key_to_error_tone
        render_inline(AlertComponent.for_flash("alert", "Denied"))

        assert_selector "i.hgi-alert-02"
        assert_text "Denied"
      end

      def test_unknown_tone_falls_back_to_info
        render_inline(AlertComponent.new(tone: :nope).with_content("x"))

        assert_selector "i.hgi-shield-01"
      end
    end
  end
end
