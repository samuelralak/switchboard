# frozen_string_literal: true

module Shared
  module Chip
    class ChipComponentPreview < ViewComponent::Preview
      def copper
        render(ChipComponent.new(tone: :copper, label: "claimed"))
      end

      def live
        render(ChipComponent.new(tone: :live, label: "open"))
      end

      def settled
        render(ChipComponent.new(tone: :settled, label: "completed"))
      end

      def fault
        render(ChipComponent.new(tone: :fault, label: "failed"))
      end

      def muted
        render(ChipComponent.new(tone: :muted, label: "draft"))
      end

      def faint_no_dot
        render(ChipComponent.new(tone: :faint, label: "12 sats"))
      end

      def without_dot
        render(ChipComponent.new(tone: :live, label: "online", dot: false))
      end

      def bordered
        render(ChipComponent.new(tone: :copper, label: "escrow", bordered: true))
      end

      def with_content_slot
        render(ChipComponent.new(tone: :settled).with_content("settled"))
      end
    end
  end
end
