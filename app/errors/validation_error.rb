# frozen_string_literal: true

# Raised when a dry-validation contract fails.
class ValidationError < ServiceError
	attr_reader :errors

	def initialize(errors)
		@errors = errors
		super("Validation failed")
	end
end
