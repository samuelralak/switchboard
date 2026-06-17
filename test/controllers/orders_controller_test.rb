# frozen_string_literal: true

require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
	MINT = "http://127.0.0.1:3338"

	test "the orders hub requires a signed-in session" do
		get orders_url
		assert_redirected_to root_path
	end

	test "the hub defaults to Buying and lists the signed-in user's placed orders, scoped to them" do
		sign_in
		mine = build_order(consumer_pubkey: @session_pubkey)
		build_order # neither party is the signed-in user

		get orders_url

		assert_response :success
		assert_select "h1", text: "Orders"
		assert_select "[role=tab][aria-selected='true']", text: /Buying/
		assert_includes response.body, mine.id.first(8) # the ledger row for my order
	end

	test "the Selling tab lists orders the signed-in user provides on" do
		sign_in
		build_order(provider_pubkey: @session_pubkey)

		get orders_url(tab: "selling")

		assert_response :success
		assert_select "[role=tab][aria-selected='true']", text: /Selling/
	end

	test "?order_id opens the order drawer with a lazy frame to the detail" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))

		get orders_url(order_id: order.id)

		assert_response :success
		assert_select "turbo-frame[src=?]", order_path(order) # the drawer lazy-loads the order detail
	end

	test "viewing an unfunded order past its funding deadline expires it on the spot" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32), funding_deadline_at: 1.minute.ago)

		get order_url(order)

		assert_response :success
		assert_equal Orders::States::EXPIRED, order.reload.current_state
	end

	test "an order_id that isn't the signed-in user's renders no drawer" do
		sign_in

		get orders_url(order_id: build_order.id) # someone else's order

		assert_response :success
		assert_select "turbo-frame", false
	end

	test "the Selling tab shows the empty state with no provider orders" do
		sign_in

		get orders_url(tab: "selling")

		assert_response :success
		assert_match(/No orders to fulfill yet/, response.body)
	end

	test "the order detail surfaces the incoming request to the provider (so they can fulfill from the hub)" do
		sign_in
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32),
			entry_point: Orders::EntryPoints::CATALOG_ORDER)

		get order_url(order)

		assert_response :success
		assert_select "[data-controller='messages'][data-messages-own-value=?]", @session_pubkey
	end

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
		assert_match(/fund the escrow/i, flash[:notice]) # the consumer funds, so they are told to
	end

	test "places an hourly order escrowing the rate times the chosen hours" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 1_500, frequency: "hour")

		post orders_url, params: order_params(coordinate_for(listing)).deep_merge(order: { hours: "3" })

		order = Order.find_by(consumer_pubkey: @session_pubkey)
		assert_redirected_to order_path(order)
		assert_equal 4_500, order.amount_sats, "3 hours at 1,500 sat/hr"
		assert_match(/fund the escrow/i, flash[:notice])
	end

	test "re-ordering the same listing while one is active returns the existing order with an honest notice" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 1_500, frequency: "hour")
		post orders_url, params: order_params(coordinate_for(listing)).deep_merge(order: { hours: "2" })
		first = Order.find_by!(consumer_pubkey: @session_pubkey)

		# A different dedupe_key and different hours: the one-active-order rule must return the EXISTING order,
		# not silently create a new one at the new total nor say "Order placed".
		post orders_url, params: order_params(coordinate_for(listing)).deep_merge(order: { hours: "5" })

		assert_equal 1, Order.where(consumer_pubkey: @session_pubkey).count, "no second order is created"
		assert_redirected_to order_path(first)
		assert_equal 3_000, first.reload.amount_sats, "the original 2-hour amount is unchanged"
		assert_match(/already have an open order/i, flash[:notice])
	end

	test "claims an open request, with the signer as provider" do
		sign_in
		request = classified_event(pubkey: "b" * 64, marker: Requests::OpenRequest.marker, price: 3_000)

		post orders_url, params: order_params(coordinate_for(request))

		order = Order.find_by(provider_pubkey: @session_pubkey)
		assert_redirected_to order_path(order)
		assert_equal Orders::EntryPoints::REQUEST_CLAIM, order.entry_point
		# The claimer is the provider; the POSTER funds, so the claimer must NOT be told to fund the escrow.
		assert_match(/claimed/i, flash[:notice])
		assert_no_match(/fund the escrow/i, flash[:notice])
	end

	test "a chosen tier-2 flows through place_params to the created order" do
		sign_in
		listing = classified_event(pubkey: "a" * 64, marker: Catalog::Listing.marker, price: 2_000)

		post orders_url, params: order_params(coordinate_for(listing)).deep_merge(order: { tier: Orders::Tiers::TIER2_ARBITER })

		assert_equal Orders::Tiers::TIER2_ARBITER, Order.find_by(consumer_pubkey: @session_pubkey).tier
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

	test "the consumer records a release on a funded order" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		post order_release_url(order), params: release_payload, as: :json

		assert_response :created
		assert order.reload.release.present?
		assert_equal Orders::States::FUNDED, order.current_state, "release does not advance the state machine"
	end

	test "a non-consumer cannot record a release" do
		sign_in
		order = build_order(provider_pubkey: @session_pubkey, consumer_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		post order_release_url(order), params: release_payload, as: :json

		assert_redirected_to root_path
		assert_nil order.reload.release
	end

	test "a delivered + released funded order shows the awaiting-redemption state to the consumer" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }
		Orders::MarkDelivered.call(order:, **delivery_payload[:delivery]) # a release reflects only after delivery
		Orders::MarkReleased.call(order:, reveal_event_id: SecureRandom.hex(32), released_at: Time.current.to_i)

		get order_path(order)

		assert_response :success
		assert_includes response.body, "Released, awaiting redemption"
		assert_not_includes response.body, "Release escrow", "the release button is gone once released"
	end

	test "release on a non-funded order is rejected with a flash redirect, recording nothing" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32)) # awaiting_funding

		post order_release_url(order), params: release_payload, as: :json

		assert_redirected_to root_path
		assert flash[:alert].present?
		assert_nil order.reload.release
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

	test "a party opens a Tier-2 dispute on a funded order" do
		sign_in
		order = funded_tier2(consumer: @session_pubkey)

		post order_dispute_url(order), params: { dispute: { reason: "Work not delivered" } }

		assert_redirected_to order_path(order)
		assert_equal Orders::States::DISPUTED, order.reload.current_state
		assert_equal "Work not delivered", order.dispute.reason
	end

	test "a dispute on a tier-1 order is rejected with a flash redirect" do
		sign_in
		order = build_order(consumer_pubkey: @session_pubkey, provider_pubkey: SecureRandom.hex(32))
		with_unspent_checkstate { Orders::Funding.call(order:, **funding_payload) }

		post order_dispute_url(order)

		assert_redirected_to root_path # ValidationError -> RedirectsOnError; no dispute recorded
		assert_nil order.reload.dispute
	end

	test "a non-party cannot open a dispute" do
		order = funded_tier2(consumer: SecureRandom.hex(32))
		sign_in

		post order_dispute_url(order)

		assert_redirected_to root_path # the involving scope hides it
		assert_nil order.reload.dispute
	end

	private

	def funded_tier2(consumer: SecureRandom.hex(32), provider: SecureRandom.hex(32))
		order = build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000,
			consumer_pubkey: consumer, provider_pubkey: provider)
		fund_tier2_order(order)
	end

	def order_params(coordinate)
		{ order: { coordinate:, mint_url: MINT, dedupe_key: SecureRandom.hex(16) } }
	end

	def delivery_payload
		hex = SecureRandom.hex(32)
		{ delivery: { delivery_event_id: hex, delivered_at: Time.current.to_i, content_hash: hex } }
	end

	def release_payload
		{ release: { reveal_event_id: SecureRandom.hex(32), released_at: Time.current.to_i } }
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
