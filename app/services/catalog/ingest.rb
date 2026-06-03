# frozen_string_literal: true

module Catalog
	# Verify and store one inbound catalog event. Returns the stored Event, or a
	# symbol for nothing stored (:ephemeral if the kind isn't persisted, :duplicate
	# if already held or older). Raises InvalidEventError on a bad event.
	class Ingest < BaseService
		option :event_data, type: Types::Strict::Hash
		option :source_relay, type: Types::Strict::String.optional, default: -> { }

		def call
			data = Events::Verify.call(event_data:)
			return :ephemeral unless Events::Kinds.storable?(data["kind"])

			Events::Upsert.call(event_data: data, source_relay:) || :duplicate
		end
	end
end
