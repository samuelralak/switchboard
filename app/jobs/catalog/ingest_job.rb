# frozen_string_literal: true

module Catalog
	# Parses the event frame and passes it to Catalog::Ingest.
	class IngestJob < ApplicationJob
		queue_as :ingest

		def perform(event_json, source_relay = nil)
			Ingest.call(event_data: JSON.parse(event_json), source_relay:)
		end
	end
end
