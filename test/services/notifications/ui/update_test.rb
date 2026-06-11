# frozen_string_literal: true

require "test_helper"

module Notifications
	module Ui
		class UpdateTest < ActiveSupport::TestCase
			test "prepends the row and replaces the badge on the recipient's stream" do
				pubkey = "a" * 64
				notification = Notification.create!(recipient_pubkey: pubkey, notification_type: "order_funded")
				stream = Notifications::Ui::State.stream(pubkey)

				calls = record_broadcasts { Notifications::Ui::Update.call(notification:) }

				expected = [
					[ :prepend, stream, Notifications::Ui::State::LIST_TARGET, Notifications::Ui::State::PARTIAL ],
					[ :replace, stream, Notifications::Ui::State::BADGE_TARGET, Notifications::Ui::State::BADGE ]
				]
				assert_equal expected, calls
			end

			test "refresh_badge replaces only the badge (no row prepend) with the recomputed count" do
				pubkey = "a" * 64
				Notification.create!(recipient_pubkey: pubkey, notification_type: "order_funded")
				stream = Notifications::Ui::State.stream(pubkey)

				calls = record_broadcasts { Notifications::Ui::Update.refresh_badge(pubkey:) }

				expected = [ [ :replace, stream, Notifications::Ui::State::BADGE_TARGET, Notifications::Ui::State::BADGE ] ]
				assert_equal expected, calls
			end

			test "refresh_row replaces the notification's own row by its dom id" do
				notification = Notification.create!(recipient_pubkey: "a" * 64, notification_type: "order_funded")
				stream = Notifications::Ui::State.stream("a" * 64)

				calls = record_broadcasts { Notifications::Ui::Update.refresh_row(notification:) }

				expected = [ [ :replace, stream, "notification_#{notification.id}", Notifications::Ui::State::PARTIAL ] ]
				assert_equal expected, calls
			end

			# refresh_row broadcasts State::PARTIAL with the (now-read) notification; verify that partial renders a
			# read row WITHOUT the unread dot or the mark-as-read wiring -- the point of marking it read.
			test "the row partial refresh_row broadcasts omits the unread dot once read" do
				read = Notification.create!(
					recipient_pubkey: "a" * 64, notification_type: "order_funded", read_at: Time.current
				)
				unread = Notification.create!(recipient_pubkey: "a" * 64, notification_type: "order_funded")
				partial = Notifications::Ui::State::PARTIAL

				read_html = ApplicationController.render(partial:, locals: { notification: read })
				unread_html = ApplicationController.render(partial:, locals: { notification: unread })

				assert_not_includes read_html, "bg-copper" # the unread dot is gone
				assert_not_includes read_html, "notification#open" # and no mark-as-read wiring on a read row
				assert_includes unread_html, "bg-copper" # the unread row still has the dot
			end

			test "the real broadcast renders the row partial without raising (helpers + routes resolve)" do
				notification = Notification.create!(
					recipient_pubkey: "a" * 64, notification_type: "order_funded", metadata: { "order_id" => SecureRandom.uuid }
				)

				assert_nothing_raised { Notifications::Ui::Update.call(notification:) }
			end

			private

			def record_broadcasts
				@calls = []
				stub_broadcast(:broadcast_prepend_to, :prepend)
				stub_broadcast(:broadcast_replace_to, :replace)
				yield
				@calls
			ensure
				restore_broadcast(:broadcast_prepend_to)
				restore_broadcast(:broadcast_replace_to)
			end

			# Shadow a Turbo broadcast method to record (action, stream, target, partial) instead of broadcasting.
			def stub_broadcast(method, action)
				recorded = @calls
				channel = Turbo::StreamsChannel.singleton_class
				channel.send(:alias_method, "__orig_#{method}", method)
				channel.send(:define_method, method) do |stream, **opts|
					recorded << [ action, stream, opts[:target], opts[:partial] ]
				end
			end

			def restore_broadcast(method)
				channel = Turbo::StreamsChannel.singleton_class
				channel.send(:alias_method, method, "__orig_#{method}")
				channel.send(:remove_method, "__orig_#{method}")
			end
		end
	end
end
