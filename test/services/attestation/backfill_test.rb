# frozen_string_literal: true

require "test_helper"

module Attestation
	# The one-time backfill: attests existing conforming listings/requests, idempotently, and only when issuing.
	class BackfillTest < ActiveSupport::TestCase
		test "attests conforming listings and requests, skipping already-attested and non-conforming" do
			service = build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1000 sat] ])
			request = build_event(extra_tags: [ [ "t", Requests::OpenRequest.marker ] ])
			already = build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1000 sat] ])
			Issue.call(event: already, manager: fake_manager)
			build_event(extra_tags: []) # unmarked: not conforming

			result = Backfill.call(manager: fake_manager)

			assert_equal 2, result[:attested], "only the two not-yet-attested conforming events are newly attested"
			assert_equal 0, result[:failed]
			assert Catalog::Listing.new(service).attested?
			assert Requests::OpenRequest.new(request).attested?
		end

		test "isolates a failing event and keeps going, counting it as failed" do
			ok = build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1000 sat] ])
			boom = build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1000 sat] ])

			result = Backfill.call(manager: manager_failing_for(boom.event_id))

			assert_equal 1, result[:attested]
			assert_equal 1, result[:failed]
			assert Catalog::Listing.new(ok).attested?
			assert_not Catalog::Listing.new(boom).attested?
		end

		test "does nothing when issuing is off" do
			build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1000 sat] ])

			with_policy("off") do
				assert_equal({ attested: 0, failed: 0 }, Backfill.call(manager: fake_manager))
			end
		end

		private

		# A relay manager that raises when publishing the label e-tagging `event_id`; other publishes are no-ops.
		def manager_failing_for(event_id)
			manager = Object.new
			manager.define_singleton_method(:publish) do |event|
				raise "relay down" if event["tags"].include?([ "e", event_id ])
			end
			manager
		end
	end
end
