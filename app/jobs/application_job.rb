# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
	# Logs and discards invalid events and unparseable frames.
	discard_on InvalidEventError do |job, error|
		Rails.logger.warn("[#{job.class.name}] rejected event: #{error.message}")
	end

	discard_on JSON::ParserError do |job, error|
		Rails.logger.error("[#{job.class.name}] unparseable frame: #{error.message}")
	end

	discard_on Dry::Types::ConstraintError do |job, error|
		Rails.logger.error("[#{job.class.name}] malformed event payload: #{error.message}")
	end
end
