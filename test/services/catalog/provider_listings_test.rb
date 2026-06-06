# frozen_string_literal: true

require "test_helper"

module Catalog
	class ProviderListingsTest < ActiveSupport::TestCase
		setup { @pubkey = "a" * 64 }

		test "returns the provider's own conforming listings, newest first" do
			older = listing_event(d_tag: "logo", title: "Logo design", created_at: 2.hours.ago)
			newer = listing_event(d_tag: "tax", title: "Tax filing", created_at: 1.hour.ago)

			results = Catalog::ProviderListings.call(pubkey: @pubkey)

			assert(results.all?(Catalog::Listing))
			assert_equal([ newer.event_id, older.event_id ], results.map { |listing| listing.event.event_id })
		end

		test "excludes other providers' listings" do
			listing_event(d_tag: "mine", title: "Mine")
			listing_event(d_tag: "theirs", title: "Theirs", pubkey: "b" * 64)

			assert_equal [ "Mine" ], Catalog::ProviderListings.call(pubkey: @pubkey).map(&:title)
		end

		test "excludes the provider's non-conforming kind-30402 events (no Switchboard marker)" do
			listing_event(d_tag: "switchboard", title: "Switchboard service")
			Event.create!( # a kind-30402 the provider published elsewhere, without the Switchboard marker
				event_id: SecureRandom.hex(32), pubkey: @pubkey, sig: SecureRandom.hex(64),
				kind: Events::Kinds::CLASSIFIED, content: "Foreign listing",
				tags: [ %w[d foreign], [ "title", "Foreign listing" ] ],
				nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
			)

			assert_equal [ "Switchboard service" ], Catalog::ProviderListings.call(pubkey: @pubkey).map(&:title)
		end

		test "includes inactive (unpublished) listings so the provider can manage them" do
			listing_event(d_tag: "live", title: "Live")
			listing_event(d_tag: "off", title: "Unpublished", status: "inactive")

			titles = Catalog::ProviderListings.call(pubkey: @pubkey).map(&:title)
			assert_includes titles, "Live"
			assert_includes titles, "Unpublished"
		end

		private

		def listing_event(d_tag:, title:, pubkey: @pubkey, status: nil, created_at: Time.current)
			tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Catalog::Listing.marker ] ]
			tags << [ "status", status ] if status
			Event.create!(
				event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
				kind: Events::Kinds::CLASSIFIED, content: title, tags:,
				nostr_created_at: created_at, raw_event: { "id" => SecureRandom.hex(32) }
			)
		end
	end
end
