# frozen_string_literal: true

module Orders
	module StatusStrip
		# The order's live state band (copper awaiting / live funded / settled released / muted refunded /
		# fault expired). Its root id is the Turbo Stream target Orders::Ui::Update replaces on each change.
		class StatusStripComponent < ApplicationComponent
			attr_reader :order

			def initialize(order:)
				@order = order
			end

			def status = @status ||= helpers.order_status(order)

			# The element id the broadcast replaces (single source: Orders::Ui::State).
			def dom_id = Orders::Ui::State.strip(order:).target
		end
	end
end
