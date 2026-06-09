# frozen_string_literal: true

module Catalog
	# Parses the event frame and passes it to Catalog::Ingest.
	class IngestJob < ApplicationJob
		queue_as :ingest

		def perform(event_json, source_relay = nil)
			event_data = JSON.parse(event_json)
			result = Ingest.call(event_data:, source_relay:)
			Cursor.new.advance(event_data["created_at"]) if result.is_a?(Event)
			result
		end
	end
end
