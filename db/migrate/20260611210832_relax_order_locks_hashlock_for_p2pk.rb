# frozen_string_literal: true

# Tier-2 (2-of-3 P2PK arbiter) locks have NO hashlock (the release gate is the arbiter, not a preimage), so
# order_locks.hashlock becomes nullable and its hex CHECK becomes "absent, or 64-hex". Tier-1 HTLC locks
# still carry a hashlock (the funding contract requires it per tier). See docs/tier2-arbiter-escrow.md.
class RelaxOrderLocksHashlockForP2pk < ActiveRecord::Migration[8.1]
	def up
		change_column_null :order_locks, :hashlock, true
		swap_hashlock_check("hashlock IS NULL OR hashlock ~ '^[0-9a-f]{64}$'")
	end

	def down
		swap_hashlock_check("hashlock ~ '^[0-9a-f]{64}$'")
		change_column_null :order_locks, :hashlock, false
	end

	private

	def swap_hashlock_check(expression)
		remove_check_constraint :order_locks, name: "order_locks_hashlock_hex"
		add_check_constraint :order_locks, expression, name: "order_locks_hashlock_hex"
	end
end
