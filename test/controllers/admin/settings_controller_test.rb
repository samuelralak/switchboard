# frozen_string_literal: true

require "test_helper"

module Admin
	# The operator default-view setting page: operator-gated, persists to AttestationSetting, rejects junk.
	class SettingsControllerTest < ActionDispatch::IntegrationTest
		teardown { Rails.application.config.x.operator_pubkeys = @saved_operators if defined?(@saved_operators) }

		test "redirects a logged-out visitor home" do
			get admin_settings_url

			assert_redirected_to root_path
		end

		test "redirects a signed-in non-operator home" do
			sign_in

			get admin_settings_url

			assert_redirected_to root_path
		end

		test "an operator sees the settings page" do
			sign_in_as_operator

			get admin_settings_url

			assert_response :success
		end

		test "an operator sets the default catalog view" do
			sign_in_as_operator

			patch admin_settings_url, params: { attestation_policy: "badge" }

			assert_redirected_to admin_settings_path
			assert_equal "badge", AttestationSetting.policy
		end

		test "rejects an unknown policy without persisting" do
			sign_in_as_operator

			patch admin_settings_url, params: { attestation_policy: "bogus" }

			assert_redirected_to admin_settings_path
			assert_nil AttestationSetting.policy
		end

		private

		def sign_in_as_operator
			sign_in
			@saved_operators = Rails.application.config.x.operator_pubkeys
			Rails.application.config.x.operator_pubkeys = [ @session_pubkey ]
		end

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
end
