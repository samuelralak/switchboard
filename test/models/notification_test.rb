# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
	def build(**attrs)
		Notification.new({ recipient_pubkey: "a" * 64, notification_type: "order_funded" }.merge(attrs))
	end

	test "is valid with a hex64 recipient, a type, and hash metadata" do
		assert build.valid?
	end

	test "requires a hex64 recipient pubkey" do
		assert build(recipient_pubkey: "nope").invalid?
		assert build(recipient_pubkey: nil).invalid?
	end

	test "requires a notification type" do
		assert build(notification_type: nil).invalid?
	end

	test "rejects non-hash metadata" do
		notification = build
		notification.metadata = "x"

		assert notification.invalid?
	end

	test "for_recipient / unseen / unread / recent scopes" do
		pk = "b" * 64
		seen = Notification.create!(
			recipient_pubkey: pk, notification_type: "t", created_at: 2.hours.ago,
			seen_at: Time.current, read_at: Time.current
		)
		fresh = Notification.create!(recipient_pubkey: pk, notification_type: "t", created_at: 1.hour.ago)
		Notification.create!(recipient_pubkey: "c" * 64, notification_type: "t") # another recipient

		assert_equal 2, Notification.for_recipient(pk).count
		assert_equal [ fresh ], Notification.for_recipient(pk).unseen.to_a
		assert_equal [ fresh ], Notification.for_recipient(pk).unread.to_a
		assert_equal [ fresh.id, seen.id ], Notification.for_recipient(pk).recent.pluck(:id) # newest first
	end
end
