# frozen_string_literal: true

require "test_helper"

module Api
	class ArbiterSignaturesControllerTest < ActionDispatch::IntegrationTest
		SECRETS = [
			%q{["P2PK",{"nonce":"01","data":"02aa"}]},
			%q{["P2PK",{"nonce":"02","data":"02bb"}]}
		].freeze

		setup { ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = TEST_ARBITER_PRIVKEY }
		teardown { ENV.delete("ESCROW_TIER2_ARBITER_PRIVKEY") }

		test "returns one arbiter signature per secret for the ruled-for party" do
			keypair = Nostr::Keygen.new.generate_key_pair
			order = ruled_order(provider: keypair.public_key.to_s, winner: "provider")

			post_signatures(order, SECRETS, keypair:)

			assert_response :ok
			assert_equal SECRETS.size, response.parsed_body["signatures"].size
			response.parsed_body["signatures"].each { |sig| assert_match(/\A[0-9a-f]{128}\z/, sig) }
		end

		test "rejects a missing Authorization header with 401" do
			order = ruled_order(provider: SecureRandom.hex(32), winner: "provider")

			post "/api/orders/#{order.id}/arbiter_signatures",
				params: JSON.generate(secrets: SECRETS), headers: { "Content-Type" => "application/json" }

			assert_response :unauthorized
		end

		test "forbids the losing party with an opaque 403" do
			keypair = Nostr::Keygen.new.generate_key_pair # the consumer, but the ruling favoured the provider
			order = ruled_order(consumer: keypair.public_key.to_s, winner: "provider")

			post_signatures(order, SECRETS, keypair:)

			assert_response :forbidden
			assert_empty response.body
		end

		test "forbids a secret not bound to the order (cross-order harvest) with 403" do
			keypair = Nostr::Keygen.new.generate_key_pair
			order = ruled_order(provider: keypair.public_key.to_s, winner: "provider")

			post_signatures(order, [ %q{["P2PK",{"nonce":"99","data":"02cc"}]} ], keypair:)

			assert_response :forbidden
		end

		test "404s when the caller is no party to the order" do
			keypair = Nostr::Keygen.new.generate_key_pair # a stranger
			order = ruled_order(provider: SecureRandom.hex(32), winner: "provider")

			post_signatures(order, SECRETS, keypair:)

			assert_response :not_found
		end

		private

		def ruled_order(winner:, provider: nil, consumer: nil)
			order = fund_tier2_order_with_secrets(SECRETS, provider:, consumer:)
			Orders::Transition.call(order:, to: Orders::States::DISPUTED)
			order.create_dispute!(opened_by_pubkey: order.consumer_pubkey, status: Orders::DisputeStatuses::OPEN)
			Orders::RuleDispute.call(order:, winner:)

			order
		end

		def post_signatures(order, secrets, keypair:)
			body = JSON.generate(secrets:)
			url = "#{origin}/api/orders/#{order.id}/arbiter_signatures"
			event = sign_nip98(keypair:, tags: nip98_tags(url:, http_method: "POST", payload: Digest::SHA256.hexdigest(body)))

			post "/api/orders/#{order.id}/arbiter_signatures",
				params: body, headers: { "Authorization" => nostr_header(event), "Content-Type" => "application/json" }
		end

		def origin = Rails.application.config.x.canonical_origin
		def nostr_header(event) = "Nostr #{Base64.strict_encode64(JSON.generate(event))}"
	end
end
