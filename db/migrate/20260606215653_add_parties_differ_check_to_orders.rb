# frozen_string_literal: true

# Escrow needs two distinct parties; back the model/contract rule with a hard DB guarantee.
class AddPartiesDifferCheckToOrders < ActiveRecord::Migration[8.1]
	def change
		add_check_constraint :orders, "consumer_pubkey <> provider_pubkey", name: "orders_parties_differ"
	end
end
