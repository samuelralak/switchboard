# frozen_string_literal: true

# Raised when a sign-in (NIP-98) request fails: a bad, expired, or already-used
# challenge nonce, the wrong kind, a stale timestamp, a method/u/challenge tag
# mismatch, or a malformed Authorization header.
class AuthenticationError < ServiceError; end
