# frozen_string_literal: true

require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
	test "requires login" do
		get messages_url

		assert_redirected_to root_path
	end

	test "shows the provider's orders as conversations joined to the service" do
		sign_in
		listing = classified_event(pubkey: @session_pubkey, marker: Catalog::Listing.marker, price: 5_000, d: "rev")
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32),
			listing_coordinate: coordinate_for(listing), amount_sats: 5_000)

		get messages_url

		assert_response :success
		assert_select "a[href=?]", message_path(order.id)
		assert_match(/Svc/, response.body) # the joined service title from the ingested listing
	end

	test "an order whose listing is not ingested still renders, with a fallback name" do
		sign_in
		build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32))

		get messages_url

		assert_response :success
		assert_match(/Escrow order/, response.body)
	end

	test "shows the empty state when the provider has no orders" do
		sign_in

		get messages_url

		assert_response :success
		assert_match(/No requests yet/, response.body)
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
