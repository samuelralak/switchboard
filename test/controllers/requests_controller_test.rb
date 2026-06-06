# frozen_string_literal: true

require "test_helper"

class RequestsControllerTest < ActionDispatch::IntegrationTest
	test "index, new, and preview require a signed-in session" do
		get requests_url
		assert_redirected_to root_path

		get new_request_url
		assert_redirected_to root_path

		post request_preview_url
		assert_redirected_to root_path
	end

	test "My requests renders only the signed-in user's own requests" do
		sign_in
		request_event(title: "My diagnose request", pubkey: @session_pubkey)
		request_event(title: "Someone else's request", pubkey: "b" * 64)

		get requests_url

		assert_response :success
		assert_select "h1", text: "My requests"
		assert_includes response.body, "My diagnose request"
		assert_not_includes response.body, "Someone else's request"
	end

	test "new renders the composer, the section rail, and the preview drawer" do
		sign_in

		get new_request_url

		assert_response :success
		assert_select "form#request-form"
		assert_select "input[name=?]", "title"
		assert_select "input[name=?]", "capability"
		assert_select "input[name=?]", "budget"
		assert_select "select[name=?]", "claim_unit"
		assert_select "select[name=?]", "delivery_unit"
		assert_select "[data-request-form-target=?]", "navItem", count: 5 # the section rail (5 sections)
		assert_select "section#section-budget"
		assert_select "turbo-frame#request-preview" # inside the preview drawer
		assert_includes response.body, "Coming soon" # funding (escrow + fee) is gated
	end

	test "preview builds a draft request from form params and renders the board view" do
		sign_in

		post request_preview_url, params: {
			title: "Diagnose an engine", description: "From a video.", capability: "diagnosis",
			budget: "5000", delivery_value: "24", delivery_unit: "hours", claim_value: "3", claim_unit: "days"
		}

		assert_response :success
		assert_select "turbo-frame#request-preview"
		assert_includes response.body, "Diagnose an engine"
		assert_includes response.body, "diagnosis"
		assert_includes response.body, "5,000"
	end

	private

	# A request event by a specific author (so My requests can assert own-vs-others filtering).
	def request_event(title:, pubkey: SecureRandom.hex(32))
		tags = [ [ "d", SecureRandom.hex(4) ], [ "title", title ], [ "t", Requests::OpenRequest.marker ] ]
		Event.create!(event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
									kind: Events::Kinds::CLASSIFIED, content: title, tags:,
									nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) })
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
