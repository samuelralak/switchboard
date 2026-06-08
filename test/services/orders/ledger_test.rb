# frozen_string_literal: true

require "test_helper"

module Orders
	class LedgerTest < ActiveSupport::TestCase
		test "returns the consumer's orders newest-first, joined to the service, with the right state" do
			consumer = SecureRandom.hex(32)
			listing = classified_event(pubkey: SecureRandom.hex(32), marker: Catalog::Listing.marker, price: 2_000)
			order = build_order(consumer_pubkey: consumer, listing_coordinate: coordinate_for(listing), amount_sats: 2_000)

			rows = Orders::Ledger.call(pubkey: consumer)

			assert_equal [ order.id ], rows.map(&:id)
			assert_equal "Svc", rows.first.title
			assert_equal 2_000, rows.first.sats
			assert rows.first.active?
		end

		test "excludes orders the user is only the provider on" do
			consumer = SecureRandom.hex(32)
			build_order(provider_pubkey: consumer, consumer_pubkey: SecureRandom.hex(32))

			assert_empty Orders::Ledger.call(pubkey: consumer)
		end

		test "falls back to a generic title when the listing is not ingested locally" do
			consumer = SecureRandom.hex(32)
			build_order(consumer_pubkey: consumer)

			assert_equal "Escrow order", Orders::Ledger.call(pubkey: consumer).first.title
		end

		test "marks a terminal order as not active" do
			consumer = SecureRandom.hex(32)
			order = build_order(consumer_pubkey: consumer)
			order.state_machine.transition_to!(Orders::States::EXPIRED)

			assert_not Orders::Ledger.call(pubkey: consumer).first.active?
		end
	end
end
