# frozen_string_literal: true

module Shared
  module Lamp
    # A single status dot used in timelines and progress rails, matching the
    # prototype's lamp family. The status sets size, fill, and motion:
    #   :current  live copper-bright pulse (the active step)
    #   :done     solid copper (a completed step)
    #   :settled  steady green (a settled / confirmed step)
    #   :fault    steady red (a failed / disputed step)
    #   :future   hollow ring (an upcoming step)
    # Renders a decorative span only; carries no content.
    class LampComponent < ApplicationComponent
      STATUSES = {
        current: "h-2.5 w-2.5 rounded-full bg-lamp-live shadow-lamp animate-pulse motion-reduce:animate-none",
        done: "h-2 w-2 rounded-full bg-copper",
        settled: "h-2.5 w-2.5 rounded-full bg-lamp-settled",
        fault: "h-2.5 w-2.5 rounded-full bg-lamp-fault",
        future: "h-2 w-2 rounded-full border border-border-strong"
      }.freeze

      def initialize(status: :future)
        @status = STATUSES.key?(status.to_s.to_sym) ? status.to_s.to_sym : :future
      end

      def klass = STATUSES.fetch(@status)
    end
  end
end
