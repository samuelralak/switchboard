# frozen_string_literal: true

require "dry/validation"

# Base for dry-validation contracts.
class ApplicationContract < Dry::Validation::Contract
	config.messages.default_locale = :en
end
