# frozen_string_literal: true

require "test_helper"

module Api
	class IdentityControllerTest < ActionDispatch::IntegrationTest
		test "returns the authenticated pubkey for a valid NIP-98 GET" do
			event = sign_nip98(tags: nip98_tags(url: identity_url, http_method: "GET"))

			get "/api/identity", headers: { "Authorization" => nostr_header(event) }

			assert_response :ok
			assert_equal event["pubkey"], response.parsed_body["pubkey"]
		end

		test "rejects a missing Authorization header" do
			get "/api/identity"

			assert_response :unauthorized
		end

		test "rejects a tampered event" do
			event = sign_nip98(tags: nip98_tags(url: identity_url, http_method: "GET"))
			event["content"] = "tampered"

			get "/api/identity", headers: { "Authorization" => nostr_header(event) }

			assert_response :unauthorized
		end

		test "rejects a method mismatch" do
			event = sign_nip98(tags: nip98_tags(url: identity_url, http_method: "POST"))

			get "/api/identity", headers: { "Authorization" => nostr_header(event) }

			assert_response :unauthorized
		end

		test "rejects a u tag bound to a different path" do
			event = sign_nip98(tags: nip98_tags(url: "#{origin}/api/elsewhere", http_method: "GET"))

			get "/api/identity", headers: { "Authorization" => nostr_header(event) }

			assert_response :unauthorized
		end

		private

		def origin = Rails.application.config.x.canonical_origin
		def identity_url = "#{origin}/api/identity"
		def nostr_header(event) = "Nostr #{Base64.strict_encode64(JSON.generate(event))}"
	end
end
