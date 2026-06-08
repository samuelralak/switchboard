# frozen_string_literal: true

module Orders
	# Statesman machine for Order. The after_transition callbacks update the current_state cache and record the
	# settlement effect in the same transaction as the transition.
	class StateMachine
		include Statesman::Machine

		States::ALL.each do |state_name|
			state state_name, initial: state_name == States::AWAITING_FUNDING
		end

		States::TRANSITIONS.each do |from, to|
			transition(from:, to:)
		end

		# Cache the ledger head. save(validate: false) skips validations because this runs inside statesman's
		# transition savepoint, where the ledger is already the source of truth.
		after_transition do |order, transition|
			order.current_state = transition.to_state
			order.save!(validate: false)
		end

		# One settlement per order; UNIQUE(order_id) on order_effects makes a second physically impossible.
		after_transition(from: States::FUNDED, to: States::RELEASED) do |order, _t|
			order.effects.create!(kind: States::RELEASED)
		end

		after_transition(from: States::FUNDED, to: States::REFUNDED) do |order, _t|
			order.effects.create!(kind: States::REFUNDED)
		end
	end
end
