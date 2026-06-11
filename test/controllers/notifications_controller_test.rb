# frozen_string_literal: true

require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
	test "index, seen, and update require a signed-in session" do
		get notifications_url
		assert_redirected_to root_path

		post seen_notifications_url
		assert_redirected_to root_path

		patch notification_url("any-id")
		assert_redirected_to root_path
	end

	test "index lists the signed-in user's notifications, not others'" do
		sign_in
		Notification.create!(
			recipient_pubkey: @session_pubkey, notification_type: "order_funded",
			metadata: { "order_id" => SecureRandom.uuid }
		)
		Notification.create!(recipient_pubkey: "b" * 64, notification_type: "order_delivered") # another recipient

		get notifications_url

		assert_response :success
		assert_select "h1", text: "Notifications"
		assert_includes response.body, "Your order was funded"
		assert_not_includes response.body, "Your order was delivered" # the other recipient's notification
	end

	test "seen marks the user's unseen notifications seen and returns no content" do
		sign_in
		notification = Notification.create!(recipient_pubkey: @session_pubkey, notification_type: "order_funded")

		post seen_notifications_url

		assert_response :no_content
		assert_not_nil notification.reload.seen_at
	end

	test "update marks the user's own notification read; another recipient's id is a silent no-op" do
		sign_in
		mine = Notification.create!(recipient_pubkey: @session_pubkey, notification_type: "order_delivered")
		theirs = Notification.create!(recipient_pubkey: "b" * 64, notification_type: "order_delivered")

		patch notification_url(mine)
		assert_response :no_content
		assert_not_nil mine.reload.read_at

		patch notification_url(theirs) # not the signed-in recipient
		assert_response :no_content # no error, no existence leak
		assert_nil theirs.reload.read_at # untouched
	end

	private

	def sign_in
		keypair = Nostr::Keygen.new.generate_key_pair
		@session_pubkey = keypair.public_key.to_s
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
