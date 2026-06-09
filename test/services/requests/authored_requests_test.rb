# frozen_string_literal: true

require "test_helper"

module Requests
	class AuthoredRequestsTest < ActiveSupport::TestCase
		setup { @pubkey = "a" * 64 }

		test "returns the poster's own conforming requests, newest first" do
			older = request_event(d_tag: "logo", title: "Logo redraw", created_at: 2.hours.ago)
			newer = request_event(d_tag: "tax", title: "Tax help", created_at: 1.hour.ago)

			results = Requests::AuthoredRequests.call(pubkey: @pubkey)

			assert(results.all?(Requests::OpenRequest))
			assert_equal([ newer.event_id, older.event_id ], results.map { |request| request.event.event_id })
		end

		test "excludes other posters' requests" do
			request_event(d_tag: "mine", title: "Mine")
			request_event(d_tag: "theirs", title: "Theirs", pubkey: "b" * 64)

			assert_equal [ "Mine" ], Requests::AuthoredRequests.call(pubkey: @pubkey).map(&:title)
		end

		test "excludes the poster's service listings (same kind 30402, no request marker)" do
			request_event(d_tag: "need", title: "Open need")
			Event.create!( # a kind-30402 listing the poster published, without the request marker
				event_id: SecureRandom.hex(32), pubkey: @pubkey, sig: SecureRandom.hex(64),
				kind: Events::Kinds::CLASSIFIED, content: "A service listing",
				tags: [ %w[d svc], [ "title", "A service listing" ], [ "t", Catalog::Listing.marker ] ],
				nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
			)

			assert_equal [ "Open need" ], Requests::AuthoredRequests.call(pubkey: @pubkey).map(&:title)
		end

		test "includes withdrawn (inactive) requests so the poster can re-post them" do
			request_event(d_tag: "open", title: "Open need")
			request_event(d_tag: "gone", title: "Withdrawn need", status: "inactive")

			titles = Requests::AuthoredRequests.call(pubkey: @pubkey).map(&:title)
			assert_includes titles, "Open need"
			assert_includes titles, "Withdrawn need"
		end

		private

		def request_event(d_tag:, title:, pubkey: @pubkey, status: nil, created_at: Time.current)
			tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Requests::OpenRequest.marker ] ]
			tags << [ "status", status ] if status
			Event.create!(
				event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
				kind: Events::Kinds::CLASSIFIED, content: title, tags:,
				nostr_created_at: created_at, raw_event: { "id" => SecureRandom.hex(32) }
			)
		end
	end
end
