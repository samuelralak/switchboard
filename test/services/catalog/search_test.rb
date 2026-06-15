# frozen_string_literal: true

require "test_helper"

module Catalog
	class SearchTest < ActiveSupport::TestCase
		test "returns recent active classified listings, newest first" do
			older = build_event(title: "Logo design", d: "logo", created_at: 2.hours.ago)
			newer = build_event(title: "Tax filing", d: "tax", created_at: 1.hour.ago)

			results = Catalog::Search.call

			assert results.all?(Catalog::Listing)
			assert_equal([ newer.event_id, older.event_id ], results.map { |listing| listing.event.event_id })
		end

		test "narrows to listings matching the free-text query" do
			build_event(title: "Logo design", d: "logo")
			build_event(title: "Tax filing", d: "tax")

			assert_equal [ "Logo design" ], Catalog::Search.call(query: "logo").map(&:title)
		end

		test "excludes non-classified and expired events" do
			build_event(title: "Live service", d: "live")
			build_event(title: "Expired service", d: "exp", expiration: 1.hour.ago)
			build_event(kind: 1, title: "A note")

			assert_equal [ "Live service" ], Catalog::Search.call.map(&:title)
		end

		test "caps results at shown" do
			3.times { |i| build_event(title: "Service #{i}", d: "svc-#{i}") }

			assert_equal 2, Catalog::Search.call(shown: 2).size
		end

		test "matches on description and capability, not only the title" do
			build_event(title: "Service A", content: "expert WORDPRESS migration", d: "a")
			build_event(title: "Service B", d: "b", extra_tags: [ [ "l", "kubernetes", "x.capability" ] ])
			build_event(title: "Service C", d: "c")

			assert_equal [ "Service A" ], Catalog::Search.call(query: "wordpress").map(&:title)
			assert_equal [ "Service B" ], Catalog::Search.call(query: "kubernetes").map(&:title)
		end

		test "matches a query that spans the title and description" do
			build_event(title: "Wordpress Migration", content: "Service for moving your site", d: "wp")
			build_event(title: "Other", d: "o")

			assert_equal [ "Wordpress Migration" ], Catalog::Search.call(query: "migration service").map(&:title)
		end

		test "excludes unpublished listings whose status tag is not active" do
			build_event(title: "Active service", d: "act")
			build_event(title: "Unpublished service", d: "off", extra_tags: [ %w[status inactive] ])

			assert_equal [ "Active service" ], Catalog::Search.call.map(&:title)
		end

		test "the limit applies to visible listings, not starved by newer unpublished ones" do
			build_event(title: "Active", d: "act", created_at: 2.hours.ago)
			build_event(title: "Unpublished newer", d: "off", created_at: 1.hour.ago, extra_tags: [ %w[status inactive] ])

			# limit fetches one row; without the SQL status filter the newer unpublished one would consume it.
			assert_equal [ "Active" ], Catalog::Search.call(limit: 1).map(&:title)
		end

		test "excludes listings from operator-flagged authors (takedown)" do
			build_event(title: "Clean service", d: "ok")
			scam = build_event(title: "Scam service", d: "scam")
			User.create!(pubkey: scam.pubkey, first_seen_at: Time.current, flagged: true)

			assert_equal [ "Clean service" ], Catalog::Search.call.map(&:title)
		end

		test "returns all listings and tags only the attested ones (a per-viewer filter, not a server cut)" do
			attested = build_event(title: "Vetted", d: "vetted", extra_tags: [ [ "t", Catalog::Listing.marker ] ])
			build_event(title: "Unvetted", d: "unvetted", extra_tags: [ [ "t", Catalog::Listing.marker ] ])
			Attestation::Issue.call(event: attested, manager: fake_manager)

			results = Catalog::Search.call

			assert_equal %w[Unvetted Vetted].sort, results.map(&:title).sort, "both listings still surface server-side"
			by_title = results.index_by(&:title)
			assert by_title["Vetted"].attested?, "the labelled listing is tagged attested"
			assert_not by_title["Unvetted"].attested?, "the unlabelled listing is not"
		end
	end
end
