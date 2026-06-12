# frozen_string_literal: true

# Add the Tier-2 `disputed` order state (between funded and a settlement). Widens the state CHECK
# constraints on orders + order_transitions, and the two active-order partial unique indexes (a disputed
# order is still open, so it must keep blocking a re-order). No behavior change: nothing transitions into
# `disputed` until the dispute lifecycle ships (Tier-2 Slice 4). See docs/tier2-arbiter-escrow.md.
class AddDisputedOrderState < ActiveRecord::Migration[8.1]
	OLD_STATES = "('awaiting_funding', 'funded', 'released', 'refunded', 'expired')"
	NEW_STATES = "('awaiting_funding', 'funded', 'disputed', 'released', 'refunded', 'expired')"
	OLD_ACTIVE = "('awaiting_funding', 'funded')"
	NEW_ACTIVE = "('awaiting_funding', 'funded', 'disputed')"

	def up
		swap_state_checks(NEW_STATES)
		swap_active_indexes(NEW_ACTIVE)
	end

	def down
		swap_state_checks(OLD_STATES)
		swap_active_indexes(OLD_ACTIVE)
	end

	private

	def swap_state_checks(states)
		swap_check :orders, "orders_current_state", "current_state IN #{states}"
		swap_check :order_transitions, "order_transitions_from_state", "from_state IN #{states}"
		swap_check :order_transitions, "order_transitions_to_state", "to_state IN #{states}"
	end

	def swap_check(table, name, expression)
		remove_check_constraint table, name: name
		add_check_constraint table, expression, name: name
	end

	def swap_active_indexes(active)
		remove_index :orders, name: "index_orders_active_claim_per_request"
		add_index :orders, :listing_coordinate, unique: true,
			where: "entry_point = 'request_claim' AND current_state IN #{active}",
			name: "index_orders_active_claim_per_request"

		remove_index :orders, name: "index_orders_active_order_per_consumer"
		add_index :orders, %i[consumer_pubkey listing_coordinate], unique: true,
			where: "entry_point = 'catalog_order' AND current_state IN #{active}",
			name: "index_orders_active_order_per_consumer"
	end
end
