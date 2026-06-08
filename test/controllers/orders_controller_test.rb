# frozen_string_literal: true

require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
	MINT = "http://127.0.0.1:3338"

	test "placing an order requires a signed-in session" do
		post orders_url, params: order_params("x")

		assert_redirected_to root_path
	end

	test "places a catalog order against a listing, with the signer as consumer" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)

		post orders_url, params: order_params(coordinate_for(listing))

		order = Order.find_by(consumer_pubkey: @session_pubkey)
		assert_redirected_to order_path(order)
		assert_equal Orders::EntryPoints::CATALOG_ORDER, order.entry_point
		assert_equal 2_000, order.amount_sats
	end

	test "claims an open request, with the signer as provider" do
		sign_in
		request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000)

		post orders_url, params: order_params(coordinate_for(request))

		order = Order.find_by(provider_pubkey: @session_pubkey)
		assert_redirected_to order_path(order)
		assert_equal Orders::EntryPoints::REQUEST_CLAIM, order.entry_point
	end

	test "a coordinate that resolves to nothing redirects with a flash error" do
		sign_in

		post orders_url, params: order_params("#{Events::Kinds::CLASSIFIED}:#{'c' * 64}:x")

		assert_redirected_to root_path
		assert flash[:alert].present?
	end

	test "a listing priced in something other than whole sats redirects with a flash error" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 10, currency: "usd")

		post orders_url, params: order_params(coordinate_for(listing))

		assert_redirected_to root_path
		assert flash[:alert].present?
	end

	test "the consumer reports the funding lock and the order becomes funded" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 1_000)
		post orders_url, params: order_params(coordinate_for(listing))
		order = Order.find_by(consumer_pubkey: @session_pubkey)

		with_unspent_checkstate { post order_funding_url(order), params: { order: funding_payload } }

		assert_redirected_to order_path(order)
		assert_equal Orders::States::FUNDED, order.reload.current_state
	end

	test "a non-consumer cannot fund the order" do
		order = build_order
		sign_in

		with_unspent_checkstate { post order_funding_url(order), params: { order: funding_payload } }

		assert_redirected_to root_path
		assert flash[:alert].present?
	end

	test "shows an order to a party and tracks its state" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 1_000)
		post orders_url, params: order_params(coordinate_for(listing))
		order = Order.find_by(consumer_pubkey: @session_pubkey)

		get order_path(order)

		assert_response :success
		assert_includes response.body, "Awaiting funding"
	end

	test "a funded order shows the consumer the release + refund actions" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		get order_path(order)

		assert_response :success
		assert_includes response.body, "Release escrow"
		assert_includes response.body, "Refund"
		assert_includes response.body, %(data-controller="settlement")
	end

	test "a funded order shows the provider the verify + redeem actions" do
		sign_in
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		get order_path(order)

		assert_response :success
		assert_includes response.body, "Verify funds"
		assert_includes response.body, "Redeem"
	end

	test "the provider records a delivery on a funded order" do
		sign_in
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		post order_delivery_url(order), params: delivery_payload, as: :json

		assert_response :created
		assert order.reload.delivery.present?
	end

	test "a non-provider cannot record a delivery" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		post order_delivery_url(order), params: delivery_payload, as: :json

		assert_redirected_to root_path
		assert_nil order.reload.delivery
	end

	test "settle re-derives a funded order to released once the mint shows the redeemed proof" do
		sign_in
		preimage = SecureRandom.hex(32)
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload(preimage:)) }
		y = order.reload.proofs.first.proof_y
		spent = [ Cashu::ProofState.new(y:, state: "SPENT", witness: { preimage: }.to_json) ]

		with_checkstate(spent) { post settle_order_url(order) }

		assert_response :ok
		assert_equal Orders::States::RELEASED, order.reload.current_state
	end

	test "a non-party cannot settle an order" do
		order = build_order(consumer_pubkey: SecureRandom.hex(32), provider_pubkey: SecureRandom.hex(32))
		sign_in

		post settle_order_url(order)

		assert_redirected_to root_path # the involving scope hides it -> RecordNotFound -> redirect
	end

	private

	def order_params(coordinate)
		{ order: { coordinate:, mint_url: MINT, dedupe_key: SecureRandom.hex(16) } }
	end

	def delivery_payload
		hex = SecureRandom.hex(32)
		{ delivery: { delivery_event_id: hex, delivered_at: Time.current.to_i, content_hash: hex } }
	end

	def funding_payload(preimage: SecureRandom.hex(32), amount: 1_000)
		{
			mint_url: MINT, hashlock: ::Digest::SHA256.hexdigest([ preimage ].pack("H*")), locktime: 1.hour.from_now.to_i,
			lock_pubkey: "02#{SecureRandom.hex(32)}", refund_pubkey: "02#{SecureRandom.hex(32)}",
			proofs: [ { y: "02#{SecureRandom.hex(32)}", amount: } ]
		}
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
