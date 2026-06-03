# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
	class TestCase
		# Run tests in parallel with specified workers
		parallelize(workers: :number_of_processors)

		# Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
		fixtures :all

		# Persist a catalog event for tests; defaults to a classified (NIP-99) listing.
		def build_event(kind: Events::Kinds::CLASSIFIED, title: "Service", content: nil, d: "svc",
										created_at: Time.current, expiration: nil, extra_tags: [])
			tags = []
			tags << [ "d", d ] << [ "title", title ] if Events::Kinds.addressable?(kind)
			tags.concat(extra_tags)
			tags << [ "expiration", expiration.to_i.to_s ] if expiration
			Event.create!(
				event_id: SecureRandom.hex(32),
				pubkey: SecureRandom.hex(32),
				sig: SecureRandom.hex(64),
				kind:,
				content: content || title,
				tags:,
				nostr_created_at: created_at,
				raw_event: { "id" => SecureRandom.hex(32) }
			)
		end
	end
end
