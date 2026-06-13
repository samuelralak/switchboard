# frozen_string_literal: true

require "test_helper"

module Orders
	module Ui
		class StateTest < ActiveSupport::TestCase
			setup { @pubkey = "a" * 64 }

			test "buying requests exclude a request that already has a live claim order (no duplicate)" do
				request_event(d_tag: "open", title: "Open request")
				request_event(d_tag: "claimed", title: "Claimed request")
				claim_order("claimed", Orders::States::AWAITING_FUNDING)

				hub = Orders::Ui::State.hub(pubkey: @pubkey, tab: "buying")

				titles = hub.buying_requests.map(&:title)
				assert_includes titles, "Open request"
				assert_not_includes titles, "Claimed request", "a claimed request must not also list as a posted request"
			end

			test "buying requests keep a request whose prior claim expired (open to claim again)" do
				request_event(d_tag: "reopened", title: "Reopened request")
				claim_order("reopened", Orders::States::EXPIRED)

				titles = Orders::Ui::State.hub(pubkey: @pubkey, tab: "buying").buying_requests.map(&:title)
				assert_includes titles, "Reopened request"
			end

			private

			# A REQUEST_CLAIM order whose listing_coordinate points back at the poster's request (the claim binding).
			def claim_order(d_tag, state)
				build_order(
					entry_point: Orders::EntryPoints::REQUEST_CLAIM,
					consumer_pubkey: @pubkey,
					listing_coordinate: "#{Events::Kinds::CLASSIFIED}:#{@pubkey}:#{d_tag}",
					current_state: state
				)
			end

			def request_event(d_tag:, title:)
				Event.create!(
					event_id: SecureRandom.hex(32), pubkey: @pubkey, sig: SecureRandom.hex(64),
					kind: Events::Kinds::CLASSIFIED, content: title,
					tags: [ [ "d", d_tag ], [ "title", title ], [ "t", Requests::OpenRequest.marker ] ],
					nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
				)
			end
		end
	end
end
