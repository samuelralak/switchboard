# frozen_string_literal: true

require "test_helper"

module Admin
	class DisputesControllerTest < ActionDispatch::IntegrationTest
		teardown { Rails.application.config.x.operator_pubkeys = @saved_operators if defined?(@saved_operators) }

		test "redirects a logged-out visitor home" do
			get admin_disputes_url

			assert_redirected_to root_path
		end

		test "redirects a signed-in non-operator home" do
			sign_in # a random pubkey, not on the allowlist

			get admin_disputes_url

			assert_redirected_to root_path
		end

		test "lists open disputes for an operator" do
			sign_in_as_operator
			order = disputed_order

			get admin_disputes_url

			assert_response :success
			assert_select "h1", text: "Dispute rulings"
			assert_includes response.body, order.listing_coordinate
		end

		test "ruling for the provider records the outcome and redirects" do
			sign_in_as_operator
			order = disputed_order

			post rule_admin_dispute_url(order.dispute), params: { winner: "provider" }

			assert_redirected_to admin_disputes_path
			assert order.dispute.reload.ruled_for_provider?
		end

		test "a non-operator cannot rule" do
			sign_in
			order = disputed_order

			post rule_admin_dispute_url(order.dispute), params: { winner: "provider" }

			assert_redirected_to root_path
			assert order.dispute.reload.open?
		end

		test "an invalid winner is rejected and the dispute stays open" do
			sign_in_as_operator
			order = disputed_order

			post rule_admin_dispute_url(order.dispute), params: { winner: "nobody" }

			assert order.dispute.reload.open?
		end

		private

		def sign_in_as_operator
			sign_in
			@saved_operators = Rails.application.config.x.operator_pubkeys
			Rails.application.config.x.operator_pubkeys = [ @session_pubkey ]
		end

		def disputed_order
			order = fund_tier2_order
			Orders::Transition.call(order:, to: Orders::States::DISPUTED)
			order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status: Orders::DisputeStatuses::OPEN)

			order
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
