# frozen_string_literal: true

# Raised when an authenticated caller is not permitted the action on a resource (distinct from
# AuthenticationError, which is a failed sign-in). API controllers answer it with an opaque 403.
class AuthorizationError < ServiceError; end
