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

	# A gift wrap addressed to us that cannot be decrypted or fails an integrity invariant
	# (spam, corruption, forgery) is permanent: discard it, never retry-storm.
	discard_on Messages::UnwrapError do |job, error|
		Rails.logger.warn("[#{job.class.name}] discarded gift wrap: #{error.message}")
	end
end
