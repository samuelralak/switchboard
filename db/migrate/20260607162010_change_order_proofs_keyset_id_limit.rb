# frozen_string_literal: true

# A NUT-02 v2 keyset id is "01" + 32 bytes = 66 hex chars, so the original varchar(64) truncated real
# mint keyset ids. Widen to 66 (matching proof_y).
class ChangeOrderProofsKeysetIdLimit < ActiveRecord::Migration[8.1]
	def up
		change_column :order_proofs, :keyset_id, :string, limit: 66
	end

	def down
		change_column :order_proofs, :keyset_id, :string, limit: 64
	end
end
