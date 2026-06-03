# frozen_string_literal: true

require "test_helper"
require "nostr"

class SessionsControllerTest < ActionDispatch::IntegrationTest
	test "challenge issues a single-use nonce" do
		post session_challenge_url

		assert_response :success
		assert_match(/\A[a-f0-9]{64}\z/, response.parsed_body["challenge"])
	end

	test "create finds-or-creates the user and starts a session for a valid event" do
		event = sign_for(LoginChallenge.issue.nonce)

		post session_url, headers: auth_header(event)

		assert_response :created
		user = User.find_by(pubkey: event["pubkey"])
		assert_not_nil user
		assert_equal 1, user.sessions.count
	end

	test "rejects a replayed event (single-use nonce)" do
		event = sign_for(LoginChallenge.issue.nonce)

		post session_url, headers: auth_header(event)
		assert_response :created

		post session_url, headers: auth_header(event)
		assert_response :unauthorized
	end

	test "rejects an unknown nonce" do
		post session_url, headers: auth_header(sign_for(SecureRandom.hex(32)))

		assert_response :unauthorized
	end

	test "rejects a tampered event" do
		event = sign_for(LoginChallenge.issue.nonce)
		event["content"] = "tampered"

		post session_url, headers: auth_header(event)

		assert_response :unauthorized
	end

	test "rejects a malformed authorization header" do
		post session_url, headers: { "Authorization" => "Nostr not-valid-base64!!" }

		assert_response :unauthorized
	end

	test "destroy terminates the session" do
		event = sign_for(LoginChallenge.issue.nonce)
		post session_url, headers: auth_header(event)
		user = User.find_by(pubkey: event["pubkey"])
		assert_equal 1, user.sessions.count

		delete session_url

		assert_response :see_other
		assert_equal 0, user.sessions.count
	end

	private

	def sign_for(nonce, http_method: "POST")
		tags = [ [ "u", verify_url ], [ "method", http_method ], [ "challenge", nonce ] ]
		keypair = Nostr::Keygen.new.generate_key_pair
		pubkey = keypair.public_key.to_s
		created_at = Time.now.to_i
		id = Digest::SHA256.hexdigest(JSON.generate([ 0, pubkey, created_at, Events::Kinds::HTTP_AUTH, tags, "" ]))
		sig = Nostr::Crypto.new.sign_message(id, keypair.private_key).to_s
		{
			"id" => id, "pubkey" => pubkey, "created_at" => created_at,
			"kind" => Events::Kinds::HTTP_AUTH, "tags" => tags, "content" => "", "sig" => sig
		}
	end

	def auth_header(event)
		{ "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
