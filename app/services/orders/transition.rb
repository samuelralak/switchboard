# frozen_string_literal: true

module Orders
	# Advance an order to `to`, the only writer of the statesman ledger. Serializes on the order row
	# (Events::Upsert's pessimistic idiom) so concurrent writers can't race the ledger; reads state fresh under
	# the lock and no-ops if already there, so a redelivered observation is idempotent.
	class Transition < BaseService
		option :order
		option :to, type: Types::Coercible::String
		option :metadata, type: Types::Strict::Hash, default: -> { {} }

		def call
			Order.transaction do |txn|
				advanced = order.with_lock { advance! }
				# Broadcast the new state + notify the affected party only AFTER the (outermost) commit, mirroring
				# Events::Upsert's txn.after_commit -> Catalog::Ui::Update. Never push a phantom on a rollback.
				txn.after_commit { broadcast_and_notify } if advanced
			end
			order
		rescue Statesman::TransitionFailedError, Statesman::GuardFailedError
			# no path (TransitionFailed) or a tier/role guard rejected it (GuardFailed): both are illegal here.
			raise IllegalTransitionError, "order #{order.id}: cannot transition #{order.current_state} -> #{to}"
		rescue ActiveRecord::RecordNotUnique
			order.reload # settlement effect already recorded: a settlement landed concurrently
		end

		private

		# Live update + the recipient notification for the new state. Both are best-effort observers that run
		# AFTER commit: a broadcast or notification failure is reported, never raised, so it cannot 500 a request
		# whose money-path state has already committed.
		def broadcast_and_notify
			Orders::Ui::Update.call(order:)
			Notifications::ForOrder.call(order:, event: order.current_state)
		rescue StandardError => e
			Rails.error.report(e, handled: true, context: { order_id: order.id, to: })
		end

		# Returns the transition (truthy) when it advanced, or nil when already at `to` (idempotent no-op).
		def advance!
			machine = order.state_machine
			return if machine.current_state(force_reload: true) == to

			machine.transition_to!(to, metadata)
		end
	end
end
