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
				# Broadcast the new state to open tracking pages only AFTER the (outermost) commit, mirroring
				# Events::Upsert's txn.after_commit -> Catalog::Ui::Update. Never push a phantom on a rollback.
				txn.after_commit { Orders::Ui::Update.call(order:) } if advanced
			end
			order
		rescue Statesman::TransitionFailedError
			raise IllegalTransitionError, "order #{order.id}: no transition #{order.current_state} -> #{to}"
		rescue ActiveRecord::RecordNotUnique
			order.reload # settlement effect already recorded: a settlement landed concurrently
		end

		private

		# Returns the transition (truthy) when it advanced, or nil when already at `to` (idempotent no-op).
		def advance!
			machine = order.state_machine
			return if machine.current_state(force_reload: true) == to

			machine.transition_to!(to, metadata)
		end
	end
end
