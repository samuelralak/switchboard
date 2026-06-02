# frozen_string_literal: true

module Shared
  module Chip
    # Maps a domain state (order / escrow / listing lifecycle) to a tone-coded
    # chip. Each known state resolves to a ChipComponent tone and a short mono
    # label; unknown states fall back to a neutral chip showing the raw state.
    class StateChipComponent < ApplicationComponent
      STATES = {
        completed: { tone: :settled, label: "completed" },
        settling: { tone: :settled, label: "settling" },
        verifying_delivery: { tone: :copper, label: "verifying" },
        awaiting_fulfillment: { tone: :live, label: "awaiting" },
        accepted: { tone: :live, label: "accepted" },
        open: { tone: :live, label: "open" },
        claimed: { tone: :copper, label: "claimed" },
        escrow_locking: { tone: :copper, label: "escrow" },
        refunding: { tone: :copper, label: "refunding" },
        received: { tone: :copper, label: "received" },
        validating: { tone: :copper, label: "validating" },
        routing: { tone: :copper, label: "routing" },
        expired: { tone: :fault, label: "expired" },
        refunded: { tone: :fault, label: "refunded" },
        failed: { tone: :fault, label: "failed" },
        cancelled: { tone: :neutral, label: "cancelled" }
      }.freeze

      def initialize(state:)
        @state = state
      end

      def tone = entry[:tone]
      def label = entry[:label]

      private

      def entry
        @entry ||= STATES.fetch(@state.to_s.to_sym, { tone: :neutral, label: @state.to_s })
      end
    end
  end
end
