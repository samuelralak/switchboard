# frozen_string_literal: true

module Orders
	# Either party opens a Tier-2 dispute on a funded order: it records the dispute and moves the order to
	# `disputed`, atomically. Idempotent -- a second open returns the existing dispute's order. Tier-1 orders,
	# non-parties, and non-funded orders are rejected. The platform arbiter rules it later (Orders::RuleDispute,
	# Slice 4.3); the consumer keeps the post-locktime refund backstop throughout.
	class OpenDispute < BaseService
		option :order
		option :opened_by_pubkey, type: Types::Strict::String
		option :reason, type: Types::Strict::String.optional, default: -> { }

		def call
			return order if order.dispute.present?

			ensure_disputable!
			Order.transaction do
				order.create_dispute!(opened_by_pubkey:, reason:, status: Orders::DisputeStatuses::OPEN)
				Orders::Transition.call(order:, to: Orders::States::DISPUTED)
			end
			order
		rescue ActiveRecord::RecordNotUnique
			order.reload # a dispute opened concurrently
		end

		private

		def ensure_disputable!
			raise ValidationError, { tier: [ "only a tier-2 order can be disputed" ] } unless order.tier2?
			raise IllegalTransitionError, "cannot dispute a #{order.current_state} order" unless funded?
			raise ValidationError, { opened_by_pubkey: [ "must be a party to the order" ] } unless party?
			# A recorded release means the consumer already co-signed to authorize the provider; they cannot then
			# claw it back via a dispute (and a ruling must never collide with an already-authorized release).
			raise IllegalTransitionError, "cannot dispute an order whose release was authorized" if order.release.present?
		end

		def funded?
			order.current_state == Orders::States::FUNDED
		end

		def party?
			[ order.consumer_pubkey, order.provider_pubkey ].include?(opened_by_pubkey)
		end
	end
end
