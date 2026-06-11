# frozen_string_literal: true

require "application_system_test_case"

# Verifies the top-bar notifications bell in a real browser: the unseen badge, the dropdown listing, and
# opening it marking everything seen (the badge clears). The live Turbo-Stream append is unit-covered by
# Notifications::Ui::UpdateTest (the test cable adapter is per-process, so a cross-process push can't be
# asserted here).
class NotificationsBellTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@pubkey = keypair.public_key.to_s
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "the bell shows the unseen badge, lists notifications, and clears the badge when opened" do
		# Recorded before sign-in so the post-login render already carries it (the bell needs no signer).
		Notification.create!(
			recipient_pubkey: @pubkey, notification_type: "order_funded", metadata: { "order_id" => SecureRandom.uuid }
		)
		sign_in_with_nsec

		assert_selector "#notifications-badge", text: "1"
		find("[data-action~='notifications#open']").click

		assert_text "Your order was funded" # the dropdown opened and lists the notification
		assert_selector "[data-controller='notification']" # the unread row is wired to mark itself read on click
		assert_no_selector "#notifications-badge", visible: true # opening marked it seen, so the badge is hidden
	end

	test "clicking an unread notification marks it read" do
		# No order_id, so the row link falls back to the notifications feed -- a real page, no Order setup needed.
		@notification = Notification.create!(recipient_pubkey: @pubkey, notification_type: "order_funded")
		sign_in_with_nsec

		find("[data-action~='notifications#open']").click
		assert_text "Your order was funded"
		find("##{Notifications::Ui::State::LIST_TARGET} a").click

		assert_current_path notifications_path # the row link navigated to the feed
		eventually { @notification.reload.read_at.present? } # the keepalive PATCH marked it read
	end

	private

	# Poll a condition that resolves out-of-band (e.g. a keepalive PATCH landing server-side after navigation).
	def eventually(timeout: 5)
		deadline = Time.current + timeout
		until yield
			raise Minitest::Assertion, "condition not met within #{timeout}s" if Time.current > deadline

			sleep 0.1
		end
	end

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_no_button "Sign in"
	end
end
