# frozen_string_literal: true

# A single-use, short-TTL sign-in nonce: the value carried in a NIP-98 `challenge`
# tag. One is issued per sign-in attempt and claimed exactly once during verification.
class LoginChallenge < ApplicationRecord
	TTL = 2.minutes # NIP-98's window is ~60s; the slack tolerates a NIP-46 bunker round-trip

	# Issues a fresh challenge for the client to sign.
	def self.issue
		create!(nonce: SecureRandom.hex(32), expires_at: TTL.from_now)
	end

	# Atomically claims a nonce: returns it iff this caller wins the single-use race and the
	# row is unexpired and unconsumed. update_all issues ONE conditional UPDATE (the atomic
	# gate), so exactly one concurrent caller sees affected-rows == 1; validations/callbacks
	# would break that atomicity and are not needed to stamp consumed_at.
	def self.consume(nonce)
		now = Time.current
		claimable = where(nonce:, consumed_at: nil).where(expires_at: now..)
		nonce if claimable.update_all(consumed_at: now) == 1 # rubocop:disable Rails/SkipsModelValidations
	end
end
