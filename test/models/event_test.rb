# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
	test "recent orders by created_at desc, breaking ties on the lower event_id" do
		at = Time.current
		a = build_event(title: "a", d: "a", created_at: at)
		b = build_event(title: "b", d: "b", created_at: at)
		lower, higher = [ a, b ].sort_by(&:event_id)

		ordered = Event.recent.where(id: [ a.id, b.id ]).pluck(:event_id)

		assert_equal [ lower.event_id, higher.event_id ], ordered
	end

	test "treats an absurd far-future expiration as non-expiring" do
		event = build_event(title: "x", d: "x", expiration: Time.at(10**13))

		assert_nil event.expires_at
	end

	test "enforces one stored row per (pubkey, kind) for replaceable kinds" do
		pubkey = SecureRandom.hex(32)
		shared = { pubkey:, kind: 10_000, sig: SecureRandom.hex(64), content: "x",
		           tags: [], nostr_created_at: Time.current, raw_event: { "x" => 1 } }
		Event.create!(shared.merge(event_id: SecureRandom.hex(32)))

		assert_raises(ActiveRecord::RecordNotUnique) do
			Event.create!(shared.merge(event_id: SecureRandom.hex(32)))
		end
	end
end
