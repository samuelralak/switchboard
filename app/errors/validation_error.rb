# frozen_string_literal: true

# Raised when a dry-validation contract fails.
class ValidationError < ServiceError
	attr_reader :errors

	def initialize(errors)
		@errors = errors
		super("Validation failed")
	end

	# The failed rules flattened into one human sentence, for a flash/redirect. Reads @errors directly (it
	# is a dry-validation hash, not an ActiveModel errors object).
	def flash_message = @errors.values.flatten.join(", ")
end
