# frozen_string_literal: true

require "test_helper"

class StudioControllerTest < ActionDispatch::IntegrationTest
	test "index and new require a signed-in session" do
		get studio_url
		assert_redirected_to root_path

		get new_studio_listing_url
		assert_redirected_to root_path
	end

	test "index redirects to the provider's profile, where managing listings now lives" do
		sign_in

		get studio_url

		assert_redirected_to profile_path(npub: Nostr::Bech32.npub_encode(@session_pubkey))
	end

	test "new renders the authoring form, the section rail, and the on-demand preview drawer" do
		sign_in

		get new_studio_listing_url

		assert_response :success
		assert_select "form#service-form"
		assert_select "input[name=?]", "title"
		assert_select "input[name=?]", "capability"
		assert_select "select[name=?]", "schema[][type]" # the clone-template row carries the type vocab
		assert_includes response.body, "attachment"      # the new field type flows from Types::InputFieldType
		assert_select "[data-studio-target=?]", "navItem", count: 4 # the section rail
		assert_select "section#section-details"
		assert_select "turbo-frame#studio-preview" # lives inside the preview drawer now
		assert_includes response.body, "Coming soon" # automated fulfillment is gated
	end

	test "preview builds a draft listing from form params and renders the buyer view" do
		sign_in

		post studio_preview_url, params: {
			title: "Summarize a thread", description: "Tight summaries.",
			capability: "summarize", price: "120", fulfillment: "automated",
			endpoint: "https://api.example.com/fulfill"
		}

		assert_response :success
		assert_select "turbo-frame#studio-preview"
		assert_includes response.body, "Summarize a thread"
		assert_includes response.body, "summarize" # capability shown in the conformance line
		assert_includes response.body, "120"       # price tag
	end

	test "edit prefills the form for the provider's own listing, carrying its d-tag and status" do
		sign_in
		listing_event(pubkey: @session_pubkey, d_tag: "logo", title: "Logo design", status: "inactive")

		get edit_studio_listing_url(d: "logo")

		assert_response :success
		assert_select "h1", text: "Edit listing"
		assert_select "input[name=?][value=?]", "title", "Logo design"
		assert_select "input[name=?][value=?]", "d_tag", "logo"        # re-publish supersedes the same coordinate
		assert_select "input[name=?][value=?]", "status", "inactive"   # editing preserves an unpublished status
	end

	test "edit redirects to the profile when the listing is not the provider's own" do
		sign_in
		listing_event(pubkey: "b" * 64, d_tag: "theirs", title: "Theirs")

		get edit_studio_listing_url(d: "theirs")

		assert_redirected_to profile_path(npub: Nostr::Bech32.npub_encode(@session_pubkey))
	end

	test "edit redirects when the coordinate now holds an open request, not a listing" do
		sign_in
		# Requests share kind 30402; one could supersede a listing at the same d. The studio must not edit it.
		request_event(pubkey: @session_pubkey, d_tag: "shared")

		get edit_studio_listing_url(d: "shared")

		assert_redirected_to profile_path(npub: Nostr::Bech32.npub_encode(@session_pubkey))
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

	def listing_event(pubkey:, d_tag:, title:, status: nil)
		tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Catalog::Listing.marker ] ]
		tags << [ "status", status ] if status
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: title, tags:,
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
	end

	# A kind-30402 carrying the REQUEST marker at the given coordinate (an open request, not a listing).
	def request_event(pubkey:, d_tag:)
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: "need",
			tags: [ [ "d", d_tag ], %w[title Need], [ "t", Requests::OpenRequest.marker ] ],
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
