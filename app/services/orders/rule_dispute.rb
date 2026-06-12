# frozen_string_literal: true

module Orders
	# The platform operator rules an open Tier-2 dispute for one party. It records the outcome on the dispute
	# (status + ruled_at) and nothing more: it does NOT move the order (disputed -> released|refunded lands when
	# the reconcile sweep confirms the proofs SPENT, the ruling supplying the direction, see Orders::Settlement)
	# and it does NOT sign (the winning party fetches the arbiter signature afterwards over the authenticated
	# channel, Api::ArbiterSignatures). A ruling is final under a row lock: re-ruling the same way is a no-op,
	# flipping it to the other party is rejected because funds may already be moving on the first ruling.
	class RuleDispute < BaseService
		WINNERS = {
			"provider" => DisputeStatuses::RULED_FOR_PROVIDER,
			"consumer" => DisputeStatuses::RULED_FOR_CONSUMER
		}.freeze

		option :order
		option :winner, type: Types::Strict::String

		def call
			validate!

			order.dispute.with_lock do
				ensure_rulable!
				order.dispute.update!(status: ruled_status, ruled_at: Time.current) if order.dispute.open?
			end

			order.dispute
		end

		private

		def validate!
			raise ValidationError, { winner: [ "must be provider or consumer" ] } unless ruled_status
			raise IllegalTransitionError, "order #{order.id}: no dispute to rule" if order.dispute.blank?
		end

		def ensure_rulable!
			raise IllegalTransitionError, "order #{order.id}: not a disputed tier-2 order" unless disputed?
			raise IllegalTransitionError, "order #{order.id}: dispute already ruled" if conflicting_ruling?
		end

		def disputed?
			order.tier2? && order.current_state == States::DISPUTED
		end

		def conflicting_ruling?
			order.dispute.ruled? && order.dispute.status != ruled_status
		end

		def ruled_status
			WINNERS[winner]
		end
	end
end
