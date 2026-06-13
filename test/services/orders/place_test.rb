# frozen_string_literal: true

require "test_helper"

module Orders
	class PlaceTest < ActiveSupport::TestCase
		MINT = "http://127.0.0.1:3338"

		test "ordering a listing makes the actor the consumer and reads the price from the event" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)

			order = place(coordinate_for(listing), actor)

			assert_equal Orders::EntryPoints::CATALOG_ORDER, order.entry_point
			assert_equal actor.pubkey, order.consumer_pubkey
			assert_equal "a" * 64, order.provider_pubkey
			assert_equal 2_000, order.amount_sats
		end

		test "claiming a request makes the actor the provider and the request author the consumer" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000)

			order = place(coordinate_for(request), actor)

			assert_equal Orders::EntryPoints::REQUEST_CLAIM, order.entry_point
			assert_equal actor.pubkey, order.provider_pubkey
			assert_equal "b" * 64, order.consumer_pubkey
			assert_equal 3_000, order.amount_sats
		end

		test "rejects a price that is not whole sats" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 10, currency: "usd")

			assert_raises(ValidationError) { place(coordinate_for(listing), actor) }
		end

		test "rejects an unknown coordinate" do
			actor = User.create!(pubkey: SecureRandom.hex(32))

			assert_raises(NotFoundError) { place("#{Events::Kinds::CLASSIFIED}:#{'c' * 64}:missing", actor) }
		end

		test "defaults to tier-1 when no tier is chosen" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)

			assert_equal Orders::Tiers::TIER1_HTLC, place(coordinate_for(listing), actor).tier
		end

		test "forwards the chosen tier-2 to the created order" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)

			order = Orders::Place.call(coordinate: coordinate_for(listing), mint_url: MINT,
				dedupe_key: SecureRandom.hex(16), tier: Orders::Tiers::TIER2_ARBITER, actor:)

			assert_equal Orders::Tiers::TIER2_ARBITER, order.tier
		end

		test "a request claim inherits the poster's tier-2 escrow choice from the event" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000,
				extra_tags: [ [ "escrow_tier", Orders::Tiers::TIER2_ARBITER ] ])

			assert_equal Orders::Tiers::TIER2_ARBITER, place(coordinate_for(request), actor).tier
		end

		test "a request claim defaults to tier-1 when the request declares no escrow tier" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000)

			assert_equal Orders::Tiers::TIER1_HTLC, place(coordinate_for(request), actor).tier
		end

		test "a request claim honours the poster's tier and ignores the claimer's posted tier" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			# The poster funded for mediated escrow; a claimer cannot downgrade it by posting tier-1.
			request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000,
				extra_tags: [ [ "escrow_tier", Orders::Tiers::TIER2_ARBITER ] ])

			order = Orders::Place.call(coordinate: coordinate_for(request), mint_url: MINT,
				dedupe_key: SecureRandom.hex(16), tier: Orders::Tiers::TIER1_HTLC, actor:)

			assert_equal Orders::Tiers::TIER2_ARBITER, order.tier
		end

		test "rejects an order against an operator-flagged author's coordinate (takedown stops new commerce)" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)
			User.create!(pubkey: "a" * 64, first_seen_at: Time.current, flagged: true)

			assert_raises(NotFoundError) { place(coordinate_for(listing), actor) }
		end

		test "rejects a coordinate that is not kind-30402" do
			actor = User.create!(pubkey: SecureRandom.hex(32))

			assert_raises(NotFoundError) { place("1:#{'c' * 64}:x", actor) }
		end

		test "rejects an expired listing" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker,
				extra_tags: [ [ "expiration", 1.hour.ago.to_i.to_s ] ])

			assert_raises(NotFoundError) { place(coordinate_for(listing), actor) }
		end

		test "rejects an inactive (unpublished) listing" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, extra_tags: [ [ "status", "inactive" ] ])

			assert_raises(NotFoundError) { place(coordinate_for(listing), actor) }
		end

		test "rejects an event carrying both the listing and request markers" do
			actor = User.create!(pubkey: SecureRandom.hex(32))
			event = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker,
				extra_tags: [ [ "t", Requests::OpenRequest.marker ] ])

			assert_raises(NotFoundError) { place(coordinate_for(event), actor) }
		end

		private

		def place(coordinate, actor)
			Orders::Place.call(coordinate:, mint_url: MINT, dedupe_key: SecureRandom.hex(16), actor:)
		end
	end
end
