# frozen_string_literal: true

class AddFlaggedPubkeyIndexToUsers < ActiveRecord::Migration[8.1]
	def change
		# Operator takedown filters users.flagged on the two hottest public queries (catalog + request board)
		# via Event.not_from_flagged. A partial index over only flagged rows keeps that subquery an index scan
		# of the tiny flagged set, not a sequential scan of the whole (every-pubkey-ever) users table.
		add_index :users, :pubkey, where: "flagged", name: "index_users_on_pubkey_where_flagged"
	end
end
