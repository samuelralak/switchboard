# frozen_string_literal: true

require "test_helper"

class OrderTest < ActiveSupport::TestCase
	test "dedupe_key is unique" do
		key = SecureRandom.hex(16)
		build_order(dedupe_key: key)

		assert_raises(ActiveRecord::RecordNotUnique) { build_order(dedupe_key: key) }
	end

	test "amount_sats must be positive at the database" do
		order = build_order
		order.amount_sats = 0

		assert_raises(ActiveRecord::StatementInvalid) { order.save(validate: false) }
	end

	test "one active claim per request, but catalog orders are not exclusive" do
		coord = "30402:#{SecureRandom.hex(32)}:svc"
		build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord)

		assert_raises(ActiveRecord::RecordNotUnique) do
			build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord)
		end

		assert build_order(entry_point: Orders::EntryPoints::CATALOG_ORDER, listing_coordinate: coord).persisted?
	end

	test "a settled claim frees the request for a new claim" do
		coord = "30402:#{SecureRandom.hex(32)}:svc"
		build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord,
													current_state: Orders::States::RELEASED)

		assert build_order(entry_point: Orders::EntryPoints::REQUEST_CLAIM, listing_coordinate: coord).persisted?
	end

	test "a disputed catalog order still blocks a re-order (the active index includes disputed)" do
		coord = "30402:#{SecureRandom.hex(32)}:svc"
		consumer = SecureRandom.hex(32)
		build_order(listing_coordinate: coord, consumer_pubkey: consumer, current_state: Orders::States::DISPUTED)

		assert_raises(ActiveRecord::RecordNotUnique) do
			build_order(listing_coordinate: coord, consumer_pubkey: consumer)
		end
	end

	test "a tier-2 order's amount is capped below tier-1" do
		amount = Orders::Policy.tier2_max_order_sats + 1
		tier2 = Order.new(**order_defaults, tier: Orders::Tiers::TIER2_ARBITER, amount_sats: amount)
		tier1 = Order.new(**order_defaults, tier: Orders::Tiers::TIER1_HTLC, amount_sats: amount)

		assert_not tier2.valid?(:create)
		assert_includes tier2.errors[:amount_sats], "exceeds the per-order cap"
		assert tier1.valid?(:create) # the same amount is fine for tier-1 (under the higher cap)
	end

	test "rejects a non-hex pubkey" do
		order = build_order
		order.consumer_pubkey = "nothex"

		assert_not order.valid?
		assert order.errors.of_kind?(:consumer_pubkey, :invalid)
	end

	test "active scope selects awaiting_funding, funded, and disputed" do
		a = build_order
		b = build_order(current_state: Orders::States::FUNDED)
		c = build_order(current_state: Orders::States::DISPUTED)
		build_order(current_state: Orders::States::RELEASED)

		assert_equal [ a.id, b.id, c.id ].sort, Order.active.pluck(:id).sort
	end

	test "funding_due selects awaiting_funding past the deadline" do
		due = build_order(funding_deadline_at: 1.minute.ago)
		build_order(funding_deadline_at: 1.hour.from_now)
		build_order(current_state: Orders::States::FUNDED, funding_deadline_at: 1.minute.ago)

		assert_equal [ due.id ], Order.funding_due.pluck(:id)
	end

	test "rejects a consumer equal to the provider" do
		pk = SecureRandom.hex(32)
		order = Order.new(order_defaults.merge(consumer_pubkey: pk, provider_pubkey: pk))

		assert_not order.valid?
		assert order.errors[:provider_pubkey].any?
	end

	test "parties differ is enforced at the database" do
		pk = SecureRandom.hex(32)
		order = Order.new(order_defaults.merge(consumer_pubkey: pk, provider_pubkey: pk))

		assert_raises(ActiveRecord::StatementInvalid) { order.save(validate: false) }
	end

	test "rejects a mint that is not allowlisted" do
		order = Order.new(order_defaults.merge(mint_url: "https://evil.example"))

		assert_not order.valid?
		assert order.errors[:mint_url].any?
	end

	test "rejects an amount over the per-order cap" do
		order = Order.new(order_defaults.merge(amount_sats: Orders::Policy.max_order_sats + 1))

		assert_not order.valid?
		assert order.errors[:amount_sats].any?
	end

	test "current_state cannot be changed directly, bypassing the ledger" do
		order = build_order
		Orders::Transition.call(order:, to: Orders::States::FUNDED)

		assert_raises(ActiveRecord::RecordInvalid) { order.update!(current_state: Orders::States::RELEASED) }
		assert_equal Orders::States::FUNDED, order.reload.current_state
		assert_empty order.effects
	end
end
