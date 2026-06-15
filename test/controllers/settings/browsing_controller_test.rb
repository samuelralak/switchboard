# frozen_string_literal: true

require "test_helper"

module Settings
	# The per-viewer catalog-view preference: login-gated, saved onto the User projection, rejects junk. Serves
	# both the Settings form (HTML) and the on-catalog filter's quick toggle (JSON).
	class BrowsingControllerTest < ActionDispatch::IntegrationTest
		test "redirects a logged-out visitor home" do
			get settings_browsing_url

			assert_redirected_to root_path
		end

		test "a signed-in viewer sees the chooser" do
			sign_in

			get settings_browsing_url

			assert_response :success
		end

		test "saves the account default and sets the cookie in lockstep" do
			sign_in

			patch settings_browsing_url, params: { catalog_view: "verified" }

			assert_redirected_to settings_browsing_path
			assert_equal "verified", current_user.reload.catalog_view
			assert_equal "verified", cookies[:catalog_view]
		end

		test "the chooser reflects the cookie over the account (so a no-op save cannot revert it)" do
			sign_in
			current_user.update!(catalog_view: "all")
			cookies[:catalog_view] = "verified"

			get settings_browsing_url

			assert_select "input[name=catalog_view][value=verified][checked]"
		end

		test "the on-catalog toggle saves via JSON with no content" do
			sign_in

			patch settings_browsing_url, params: { catalog_view: "all" }, as: :json

			assert_response :no_content
			assert_equal "all", current_user.reload.catalog_view
		end

		test "rejects an unknown view without saving" do
			sign_in

			patch settings_browsing_url, params: { catalog_view: "bogus" }

			assert_redirected_to settings_browsing_path
			assert_nil current_user.reload.catalog_view
		end

		private

		def current_user
			User.find_by(pubkey: @session_pubkey)
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
