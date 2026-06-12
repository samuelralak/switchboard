# frozen_string_literal: true

module Admin
	# The operator's Tier-2 ruling queue: list open disputes (index) and rule one for a party (rule). Ruling
	# only records the outcome on the dispute; the order settles to released/refunded when the reconcile sweep
	# confirms the winning party's on-mint spend (Orders::Settlement reads the ruling for direction). HTML/Turbo
	# throughout -- the arbiter signing that completes the spend is the party's own JSON call (Api).
	class DisputesController < BaseController
		def index
			@disputes = OrderDispute.awaiting_ruling.includes(:order)
		end

		def rule
			dispute = OrderDispute.find(params.expect(:id))
			Orders::RuleDispute.call(order: dispute.order, winner: params.expect(:winner))

			redirect_to admin_disputes_path, notice: "Ruled for the #{params[:winner]}."
		end
	end
end
