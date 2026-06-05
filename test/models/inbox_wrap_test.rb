# frozen_string_literal: true

require "test_helper"

class InboxWrapTest < ActiveSupport::TestCase
	HEX64 = "a" * 64

	test "is valid with a hex recipient pubkey and wrap id" do
		assert build_wrap.valid?
	end

	test "rejects a non-hex recipient pubkey or wrap id" do
		assert_not build_wrap(recipient_pubkey: "nope").valid?
		assert_not build_wrap(wrap_id: "ZZZ").valid?
	end

	test "for_recipient returns only that recipient's wraps" do
		mine = create_wrap(recipient_pubkey: HEX64)
		create_wrap(recipient_pubkey: "c" * 64)
		assert_equal [ mine.id ], InboxWrap.for_recipient(HEX64).pluck(:id)
	end

	test "chronological orders by created_at then id; after_cursor never skips a wrap tied on created_at" do
		tied = 1.hour.ago.change(usec: 500_000)
		a = create_wrap(created_at: tied)
		b = create_wrap(created_at: tied)
		first, second = [ a, b ].sort_by { |w| [ w.created_at, w.id ] }

		assert_equal [ first.id, second.id ], InboxWrap.chronological.pluck(:id)
		assert_equal [ second.id ], InboxWrap.after_cursor(first.created_at, first.id).chronological.pluck(:id)
		assert_equal [ a.id, b.id ].sort, InboxWrap.after_cursor(nil, nil).pluck(:id).sort
	end

	test "unexpired excludes wraps past their horizon, and prune_expired deletes them" do
		live = create_wrap(expires_at: 1.day.from_now)
		create_wrap(expires_at: 1.minute.ago)
		assert_equal [ live.id ], InboxWrap.unexpired.pluck(:id)
		assert_equal 1, InboxWrap.prune_expired
		assert_equal [ live.id ], InboxWrap.pluck(:id)
	end

	private

	def build_wrap(**attrs)
		defaults = { recipient_pubkey: HEX64, wrap_id: "b" * 64, wrap: { "kind" => 1059 } }
		InboxWrap.new(defaults.merge(attrs))
	end

	def create_wrap(recipient_pubkey: HEX64, created_at: Time.current, expires_at: 1.day.from_now)
		wrap_id = SecureRandom.hex(32)
		wrap = { "id" => wrap_id, "kind" => 1059 }
		InboxWrap.create!(recipient_pubkey:, wrap_id:, wrap:, nostr_created_at: created_at, expires_at:, created_at:)
	end
end
