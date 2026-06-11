# frozen_string_literal: true

require "test_helper"

module Layout
	module NotificationsBell
		class NotificationsBellComponentTest < ViewComponent::TestCase
			def user(pubkey = "a" * 64)
				User.create!(pubkey:, first_seen_at: Time.current, external_identities: [])
			end

			test "renders the bell, the per-user stream, and recent notifications with an unseen badge" do
				signed_in = user
				Notification.create!(
					recipient_pubkey: signed_in.pubkey, notification_type: "order_funded",
					metadata: { "order_id" => SecureRandom.uuid }
				)

				render_inline(NotificationsBellComponent.new(user: signed_in))

				assert_selector "[data-controller='notifications']"
				assert_selector "turbo-cable-stream-source"
				assert_selector "##{Notifications::Ui::State::BADGE_TARGET}", text: "1"
				assert_selector "##{Notifications::Ui::State::LIST_TARGET} li", text: "Your order was funded"
			end

			test "shows the empty state and a hidden badge when there are no notifications" do
				render_inline(NotificationsBellComponent.new(user: user))

				assert_selector "[data-notifications-target='empty']", text: "No notifications yet"
				assert_selector "##{Notifications::Ui::State::BADGE_TARGET}", visible: false, text: "0"
			end

			test "renders a persistent polite live region for screen-reader count announcements" do
				render_inline(NotificationsBellComponent.new(user: user))

				assert_selector "[data-notifications-target='status'][role='status'][aria-live='polite']", visible: :all
			end

			# The security boundary: the stream is HMAC-signed (Turbo::StreamsChannel rejects unverified subs), so
			# the raw pubkey is never a subscribable channel. Guards against a regression to a raw cable channel.
			test "subscribes via a signed stream name, never a raw pubkey channel" do
				render_inline(NotificationsBellComponent.new(user: user))

				assert_selector "turbo-cable-stream-source[channel='Turbo::StreamsChannel'][signed-stream-name]", visible: :all
				assert_no_selector "turbo-cable-stream-source[channel*='notifications:']", visible: :all
			end

			test "an unread row shows the unread marker and wires mark-as-read on click" do
				signed_in = user
				Notification.create!(recipient_pubkey: signed_in.pubkey, notification_type: "order_funded") # read_at nil

				render_inline(NotificationsBellComponent.new(user: signed_in))

				assert_selector "[data-controller='notification'][data-action='notification#open'][data-notification-url-value]"
				assert_selector "li", text: "Unread", visible: :all
				assert_selector "##{Notifications::Ui::State::LIST_TARGET} .bg-copper", visible: :all # the unread dot
			end

			test "a read row has no unread marker and no mark-as-read wiring" do
				signed_in = user
				Notification.create!(
					recipient_pubkey: signed_in.pubkey, notification_type: "order_funded", read_at: Time.current
				)

				render_inline(NotificationsBellComponent.new(user: signed_in))

				assert_no_selector "[data-controller='notification']"
				assert_no_selector "li", text: "Unread", visible: :all
				assert_no_selector "##{Notifications::Ui::State::LIST_TARGET} .bg-copper" # no unread dot once read
			end
		end
	end
end
