# frozen_string_literal: true

# Raised when an inbound Nostr event fails structural, id, or signature checks.
class InvalidEventError < ServiceError; end
