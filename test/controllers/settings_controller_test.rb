# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
	test "requires a signed-in session" do
		get settings_url

		assert_redirected_to root_path
	end

	test "renders the relays section when signed in" do
		sign_in

		get settings_url

		assert_response :success
		assert_select "h2", text: "Relays"
		assert_includes response.body, "relay.damus.io"
	end

	private

	def sign_in
		keypair = Nostr::Keygen.new.generate_key_pair
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
