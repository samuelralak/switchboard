# frozen_string_literal: true

require "test_helper"

# The generic NIP-17 DM proof surface: session-authenticated, and it hands the browser the signed-in
# pubkey + DM relays + inbox URL via data-* attributes (the only server involvement).
class DirectMessagesControllerTest < ActionDispatch::IntegrationTest
	test "requires a signed-in session" do
		get direct_messages_url

		assert_redirected_to root_path
	end

	test "exposes the signed-in pubkey, DM relays, and inbox URL to the client" do
		pubkey = sign_in

		get direct_messages_url

		assert_response :success
		assert_select "[data-controller=dm-client]"
		assert_select "[data-dm-client-pubkey-value=?]", pubkey
		assert_select "[data-dm-client-inbox-url-value=?]", inbox_path
		assert_includes response.body, "wss://auth.nostr1.com" # the configured dm_relays, JSON-encoded
		assert_select "form[data-action=?]", "dm-client#send"
	end

	private

	def sign_in
		keypair = Nostr::Keygen.new.generate_key_pair
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
		keypair.public_key.to_s
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
