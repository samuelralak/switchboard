# frozen_string_literal: true

require "test_helper"

module Orders
	class CreateTest < ActiveSupport::TestCase
		test "opens an order in awaiting_funding with an empty ledger" do
			order = create

			assert order.persisted?
			assert_equal Orders::States::AWAITING_FUNDING, order.current_state
			assert_equal Orders::States::AWAITING_FUNDING, order.state_machine.current_state
			assert_empty order.order_transitions
		end

		test "is idempotent on dedupe_key" do
			attrs = defaults.merge(dedupe_key: SecureRandom.hex(16))
			first = Orders::Create.call(**attrs)
			second = Orders::Create.call(**attrs)

			assert_equal first.id, second.id
			assert_equal 1, Order.where(dedupe_key: attrs[:dedupe_key]).count
		end

		test "rejects a mint that is not allowlisted" do
			error = assert_raises(ValidationError) { create(mint_url: "https://evil.example") }

			assert error.errors.key?(:mint_url)
		end

		test "rejects an amount over the per-order cap" do
			error = assert_raises(ValidationError) { create(amount_sats: Orders::Policy.max_order_sats + 1) }

			assert error.errors.key?(:amount_sats)
		end

		test "rejects a tier-2 amount over the lower tier-2 cap" do
			over_tier2 = Orders::Policy.tier2_max_order_sats + 1
			error = assert_raises(ValidationError) { create(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: over_tier2) }

			assert error.errors.key?(:amount_sats)
			assert create(amount_sats: over_tier2).persisted? # the same amount is fine for tier-1 (higher cap)
		end

		test "rejects a consumer equal to the provider" do
			pk = SecureRandom.hex(32)

			assert_raises(ValidationError) { create(consumer_pubkey: pk, provider_pubkey: pk) }
		end

		test "rejects a non-hex pubkey" do
			assert_raises(ValidationError) { create(consumer_pubkey: "nothex") }
		end

		test "rejects a past funding deadline" do
			assert_raises(ValidationError) { create(funding_deadline_at: 1.minute.ago) }
		end

		test "a repeat order for a listing the consumer already has open returns the open order" do
			consumer = SecureRandom.hex(32)
			coord = "30402:#{SecureRandom.hex(32)}:svc"
			first = create(consumer_pubkey: consumer, listing_coordinate: coord, dedupe_key: SecureRandom.hex(16))
			second = create(consumer_pubkey: consumer, listing_coordinate: coord, dedupe_key: SecureRandom.hex(16))

			assert_equal first.id, second.id
			assert_equal 1, Order.active.where(consumer_pubkey: consumer, listing_coordinate: coord).count
		end

		test "a consumer can re-order the same listing once the prior order is terminal" do
			consumer = SecureRandom.hex(32)
			coord = "30402:#{SecureRandom.hex(32)}:svc"
			first = create(consumer_pubkey: consumer, listing_coordinate: coord, dedupe_key: SecureRandom.hex(16))
			Orders::Transition.call(order: first, to: Orders::States::EXPIRED)

			second = create(consumer_pubkey: consumer, listing_coordinate: coord, dedupe_key: SecureRandom.hex(16))

			assert_not_equal first.id, second.id
		end

		test "a second active claim for one request raises" do
			coord = "30402:#{SecureRandom.hex(32)}:svc"
			create(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord)

			assert_raises(ActiveRecord::RecordNotUnique) do
				create(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord,
					provider_pubkey: SecureRandom.hex(32))
			end
		end

		test "the same provider re-claiming a request returns the open claim" do
			provider = SecureRandom.hex(32)
			coord = "30402:#{SecureRandom.hex(32)}:svc"
			first = create(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord,
				provider_pubkey: provider, dedupe_key: SecureRandom.hex(16))
			second = create(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord,
				provider_pubkey: provider, dedupe_key: SecureRandom.hex(16))

			assert_equal first.id, second.id
		end

		test "re-raises when a dedupe_key is reused for a different request" do
			key = SecureRandom.hex(16)
			create(dedupe_key: key, listing_coordinate: "30402:#{SecureRandom.hex(32)}:a")

			assert_raises(ActiveRecord::RecordNotUnique) do
				create(dedupe_key: key, listing_coordinate: "30402:#{SecureRandom.hex(32)}:b")
			end
		end

		test "rejects a zero or negative amount" do
			assert_raises(ValidationError) { create(amount_sats: 0) }
			assert_raises(ValidationError) { create(amount_sats: -100) }
		end

		private

		def create(**overrides)
			Orders::Create.call(**defaults, **overrides)
		end

		def defaults
			{
				entry_point: Orders::EntryPoints::CATALOG_ORDER,
				consumer_pubkey: SecureRandom.hex(32),
				provider_pubkey: SecureRandom.hex(32),
				listing_coordinate: "30402:#{SecureRandom.hex(32)}:svc",
				amount_sats: 1_000,
				mint_url: "http://127.0.0.1:3338",
				dedupe_key: SecureRandom.hex(16),
				funding_deadline_at: 1.hour.from_now
			}
		end
	end
end
