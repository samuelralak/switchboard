# frozen_string_literal: true

require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
	test "requires login" do
		get messages_url

		assert_redirected_to root_path
	end

	test "the inbox redirects to the orders hub's Selling tab (the provider ledger folded in)" do
		sign_in

		get messages_url

		assert_redirected_to orders_path(tab: "selling")
	end

	test "a thread page (/messages/:id) still renders the order's conversation" do
		sign_in
		listing = classified_event(pubkey: @session_pubkey, marker: Catalog::Listing.marker, price: 5_000, d: "rev")
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32),
			listing_coordinate: coordinate_for(listing), amount_sats: 5_000)

		get message_url(order.id)

		assert_response :success
		assert_match(/Svc/, response.body) # the joined service title, rendered in the thread
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
