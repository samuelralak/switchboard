# frozen_string_literal: true

# Base for service objects. Provides a dry-initializer typed initializer and a `.call` class method.
class BaseService
	extend Dry::Initializer

	def self.call(...)
		new(...).call
	end
end
