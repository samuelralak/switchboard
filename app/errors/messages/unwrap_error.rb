# frozen_string_literal: true

module Messages
	# Raised by Messages::Unwrap when a gift wrap cannot be decrypted or fails any NIP-17/59
	# integrity invariant (bad signature, signed/forged rumor, non-empty seal tags,
	# impersonation). A ServiceError so the ingest job discards it (adversarial/undecryptable
	# wraps must not retry-storm) rather than retrying.
	class UnwrapError < ServiceError; end
end
