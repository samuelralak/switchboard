# frozen_string_literal: true

module Shared
  module Alert
    # A banner / callout for flash messages and inline notices, matching the
    # prototype's alert family. The tone sets border, background, and icon:
    #   :error   lamp-fault    (validation failures, errors)
    #   :info    copper        (the universal-escrow guarantee banner, accent notices)
    #   :note    neutral inset (reassurance notes)
    #   :success lamp-settled  (completed / settled confirmations)
    # Pass the message as block content; an optional title renders as a bold lead.
    class AlertComponent < ApplicationComponent
      TONES = {
        error: {
          container: "border-lamp-fault/40 bg-lamp-fault/5",
          icon: "hgi-alert-02", icon_color: "text-lamp-fault"
        },
        info: {
          container: "border-copper-dim/40 bg-copper/5",
          icon: "hgi-shield-01", icon_color: "text-copper"
        },
        note: {
          container: "border-border bg-inset",
          icon: "hgi-shield-01", icon_color: "text-copper"
        },
        success: {
          container: "border-lamp-settled/40 bg-lamp-settled/5",
          icon: "hgi-checkmark-circle-02", icon_color: "text-lamp-settled"
        }
      }.freeze

      # Rails flash keys -> tone. Unknown keys fall back to :info.
      FLASH_TONES = { "alert" => :error, "error" => :error, "success" => :success, "notice" => :info }.freeze

      def self.for_flash(key, message)
        new(tone: FLASH_TONES.fetch(key.to_s, :info)).with_content(message)
      end

      attr_reader :title

      def initialize(tone: :info, title: nil, icon: nil)
        @tone = TONES.key?(tone.to_s.to_sym) ? tone.to_s.to_sym : :info
        @title = title
        @icon = icon
      end

      def container_class = TONES.fetch(@tone)[:container]
      def icon = @icon || TONES.fetch(@tone)[:icon]
      def icon_color = TONES.fetch(@tone)[:icon_color]
    end
  end
end
