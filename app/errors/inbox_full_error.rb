# frozen_string_literal: true

# Raised when a recipient's opaque-wrap cache is at PER_RECIPIENT_QUOTA. The wrap is valid but there
# is no room, so the deposit endpoint answers 507 (distinct from a 422 malformed/forged wrap).
class InboxFullError < ServiceError; end
