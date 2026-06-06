# frozen_string_literal: true

require "test_helper"

module Requests
	class SearchTest < ActiveSupport::TestCase
		# A conforming open-request event (kind-30402 + request marker).
		def request_event(extra_tags: [], **)
			build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
		end

		test "returns recent open requests, newest first" do
			older = request_event(title: "Older need", d: "o", created_at: 2.hours.ago)
			newer = request_event(title: "Newer need", d: "n", created_at: 1.hour.ago)

			results = Requests::Search.call

			assert results.all?(OpenRequest)
			assert_equal([ newer.event_id, older.event_id ], results.map { |r| r.event.event_id })
		end

		test "narrows to requests matching the free-text query" do
			request_event(title: "Logo redraw", d: "logo")
			request_event(title: "Tax help", d: "tax")

			assert_equal [ "Logo redraw" ], Requests::Search.call(query: "logo").map(&:title)
		end

		test "excludes withdrawn (inactive) requests" do
			request_event(title: "Open need", d: "open")
			request_event(title: "Withdrawn need", d: "gone", extra_tags: [ %w[status inactive] ])

			assert_equal [ "Open need" ], Requests::Search.call.map(&:title)
		end

		# The core of the epic: requests and listings share kind 30402 and must not bleed across surfaces.
		test "the board shows only requests, never service listings" do
			request_event(title: "Open need", d: "need")
			build_event(title: "A service listing", d: "svc") # no request marker -> a catalog listing

			assert_equal [ "Open need" ], Requests::Search.call.map(&:title)
		end

		test "the catalog excludes open requests" do
			build_event(title: "A service listing", d: "svc")
			request_event(title: "Open need", d: "need")

			assert_equal [ "A service listing" ], Catalog::Search.call.map(&:title)
		end
	end
end
