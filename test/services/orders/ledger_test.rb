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

		test "query count is constant in the number of orders (batched service + delivery, no N+1)" do
			consumer = SecureRandom.hex(32)
			place = lambda do
				listing = classified_event(pubkey: SecureRandom.hex(32), marker: Catalog::Listing.marker, price: 2_000)
				build_order(consumer_pubkey: consumer, listing_coordinate: coordinate_for(listing), amount_sats: 2_000)
			end

			place.call
			one = count_queries { Orders::Ledger.call(pubkey: consumer) }
			4.times { place.call }
			five = count_queries { Orders::Ledger.call(pubkey: consumer) }

			assert_equal one, five, "ledger query count must not grow with order count (N+1 regression)"
		end

		private

		# Counts the non-schema, non-transaction SQL queries a block issues.
		def count_queries(&)
			queries = 0
			counter = lambda do |_name, _start, _finish, _id, payload|
				next if payload[:name] == "SCHEMA"
				next if payload[:sql].to_s.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

				queries += 1
			end
			ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
			queries
		end
	end
end
