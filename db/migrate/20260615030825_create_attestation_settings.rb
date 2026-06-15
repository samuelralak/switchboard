# frozen_string_literal: true

# The operator-set catalog attestation policy, persisted as a single row (see AttestationSetting). The unique
# index on `singleton` pins the table to one row; the check constraint mirrors Attestation::POLICIES at the DB.
class CreateAttestationSettings < ActiveRecord::Migration[8.1]
	def change
		create_table :attestation_settings, id: :uuid do |t|
			t.string :policy, null: false, default: "exclude"
			t.boolean :singleton, null: false, default: true

			t.timestamps
		end

		add_index :attestation_settings, :singleton, unique: true
		add_check_constraint :attestation_settings, "policy IN ('off', 'badge', 'exclude')",
			name: "attestation_settings_policy"
	end
end
