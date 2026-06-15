# frozen_string_literal: true

# The operator-set catalog attestation policy, persisted as a single row so it survives deploys and is shared
# across every web/worker machine. Read through Attestation::Policy, where the stored value wins over the ENV
# default. A unique index on `singleton` keeps the table to one row.
class AttestationSetting < ApplicationRecord
	validates :policy, inclusion: { in: Attestation::POLICIES }

	# The persisted policy, or nil when the operator has never set one (so the caller falls back to ENV/default).
	def self.policy
		first&.policy
	end

	# Create-or-update the single row. The caller validates `value` against Attestation::POLICIES first; the model
	# validation and the DB check constraint are the backstop. The bounded retry handles the (near-theoretical,
	# operator-gated) race where two first-writes both insert and the singleton unique index rejects the loser:
	# on retry `first` finds the winner's row and updates it.
	def self.assign_policy(value, attempts = 0)
		record = first || new
		record.update!(policy: value)

		record
	rescue ActiveRecord::RecordNotUnique
		raise if attempts >= 2

		assign_policy(value, attempts + 1)
	end
end
