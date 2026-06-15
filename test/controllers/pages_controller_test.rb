# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
	test "renders the home page at root" do
		get root_url
		assert_response :success
	end

	test "renders an ingested listing in the catalog grid" do
		build_event(title: "Logo design", d: "logo")

		get root_url

		assert_response :success
		assert_select "#catalog_listings"
		assert_includes response.body, "Logo design"
	end

	test "applies the search query" do
		build_event(title: "Logo design", d: "logo")
		build_event(title: "Tax filing", d: "tax")

		get root_url, params: { q: "logo" }

		assert_response :success
		assert_includes response.body, "Logo design"
		assert_not_includes response.body, "Tax filing"
	end

	test "tolerates a non-hash search param without erroring" do
		get root_url, params: { search: "foo" }
		assert_response :success

		get root_url, params: { search: [ "a" ] }
		assert_response :success
	end

	test "defaults the catalog view to the operator default and shows the verification filter" do
		# Suite default policy is badge -> default view "all", feature enabled (R_op issuer present).
		get root_url

		assert_includes response.body, 'data-catalog-attestation-value="all"'
		assert_includes response.body, "Filter by platform verification"
	end

	test "a valid catalog_view cookie overrides the operator default and cloaks unverified cards" do
		cookies[:catalog_view] = "verified"

		get root_url

		assert_includes response.body, 'data-catalog-attestation-value="verified"'
		assert_includes response.body, "catalog-verified-cloak"
	end

	test "an invalid catalog_view cookie falls back to the operator default" do
		cookies[:catalog_view] = "bogus"

		get root_url

		assert_includes response.body, 'data-catalog-attestation-value="all"'
	end

	test "an invalid cookie falls through to a signed-in viewer's saved account default, not the operator default" do
		sign_in
		current_user.update!(catalog_view: "verified")
		cookies[:catalog_view] = "bogus"

		get root_url

		assert_includes response.body, 'data-catalog-attestation-value="verified"'
	end

	test "the cookie wins over a signed-in viewer's saved account default" do
		sign_in
		current_user.update!(catalog_view: "all")
		cookies[:catalog_view] = "verified"

		get root_url

		assert_includes response.body, 'data-catalog-attestation-value="verified"'
	end

	test "with attestation off the filter is hidden and the view is forced to all" do
		with_policy("off") do
			get root_url
		end

		assert_includes response.body, 'data-catalog-attestation-value="all"'
		assert_not_includes response.body, "Filter by platform verification"
	end

	test "renders the terms & privacy page publicly" do
		get terms_url

		assert_response :success
		assert_select "h1", text: /Terms/
	end

	test "renders the donation page publicly with the addresses" do
		get donate_url

		assert_response :success
		assert_includes response.body, "afraidstorm87@walletofsatoshi.com"
		assert_includes response.body, "bc1q2kkvcqkn9s5alhcr8uw0t80kga994eukzmxsa3"
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
