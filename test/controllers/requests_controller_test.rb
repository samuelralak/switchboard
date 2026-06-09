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

	test "My requests lists the poster's own requests with a d-tag-keyed edit link, including withdrawn ones" do
		sign_in
		request_event(title: "Open need", pubkey: @session_pubkey, d_tag: "open")
		request_event(title: "Withdrawn need", pubkey: @session_pubkey, d_tag: "gone", status: "inactive")

		get requests_url

		assert_response :success
		assert_includes response.body, "Open need"
		assert_includes response.body, "Withdrawn need" # kept so the poster can re-post it
		assert_select "a[href=?]", edit_request_path(d: "open")
		assert_select "a[href=?]", edit_request_path(d: "gone")
	end

	test "edit prefills the form for the poster's own request, carrying its d-tag and status" do
		sign_in
		request_event(title: "Logo redraw", pubkey: @session_pubkey, d_tag: "logo", status: "inactive")

		get edit_request_url(d: "logo")

		assert_response :success
		assert_select "h1", text: "Edit request"
		assert_select "input[name=?][value=?]", "title", "Logo redraw"
		assert_select "input[name=?][value=?]", "d_tag", "logo"       # re-post supersedes the same coordinate
		assert_select "input[name=?][value=?]", "status", "inactive"  # editing preserves a withdrawn status
	end

	test "edit redirects to My requests when the request is not the poster's own" do
		sign_in
		request_event(title: "Theirs", pubkey: "b" * 64, d_tag: "theirs")

		get edit_request_url(d: "theirs")

		assert_redirected_to requests_path
	end

	test "edit redirects when the coordinate now holds a service listing, not an open request" do
		sign_in
		# Listings share kind 30402; one could supersede a request at the same d. My requests must not edit it.
		listing_event(pubkey: @session_pubkey, d_tag: "shared")

		get edit_request_url(d: "shared")

		assert_redirected_to requests_path
	end

	test "My requests shows the consumer's placed orders, opening each in the order drawer" do
		sign_in
		listing = classified_event(pubkey: SecureRandom.hex(32), marker: Catalog::Listing.marker, price: 2_000)
		order = build_order(consumer_pubkey: @session_pubkey, listing_coordinate: coordinate_for(listing))

		get requests_url

		assert_response :success
		assert_select "a[href=?]", requests_path(order_id: order.id) # the row opens the URL-driven drawer
		assert_includes response.body, "Svc" # the joined listing title
	end

	test "?order_id opens the order drawer with a lazy frame to the order detail" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))

		get requests_url(order_id: order.id)

		assert_response :success
		assert_select "turbo-frame[src=?]", order_path(order) # the drawer lazy-loads the detail
	end

	test "?order_id for an order that isn't yours renders no drawer" do
		sign_in

		get requests_url(order_id: build_order.id) # someone else's order

		assert_response :success
		assert_select "turbo-frame", false
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
	def request_event(title:, pubkey: SecureRandom.hex(32), d_tag: SecureRandom.hex(4), status: nil)
		tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Requests::OpenRequest.marker ] ]
		tags << [ "status", status ] if status
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: title, tags:,
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
	end

	# A kind-30402 carrying the LISTING marker at the given coordinate (a service listing, not a request).
	def listing_event(pubkey:, d_tag:)
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: "service",
			tags: [ [ "d", d_tag ], %w[title Service], [ "t", Catalog::Listing.marker ] ],
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
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
