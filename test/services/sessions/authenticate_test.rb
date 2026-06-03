# frozen_string_literal: true

require "test_helper"
require "nostr"

module Sessions
	class AuthenticateTest < ActiveSupport::TestCase
		test "returns the user for a valid event bound to an outstanding nonce" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce))

			user = authenticate(event)

			assert_instance_of User, user
			assert_equal event["pubkey"], user.pubkey
		end

		test "consumes the nonce so it cannot be reused" do
			nonce = LoginChallenge.issue.nonce
			authenticate(sign(tags: auth_tags(challenge: nonce)))

			assert_nil LoginChallenge.consume(nonce)
		end

		test "rejects an unknown or already-used nonce" do
			assert_raises(AuthenticationError) { authenticate(sign(tags: auth_tags(challenge: SecureRandom.hex(32)))) }
		end

		test "rejects a missing challenge tag" do
			event = sign(tags: auth_tags(challenge: nil))

			assert_raises(AuthenticationError) { authenticate(event) }
		end

		test "rejects malformed tags without raising a 500" do
			assert_raises(AuthenticationError) { authenticate({ "tags" => "garbage" }) }
			assert_raises(AuthenticationError) { authenticate({ "tags" => [ 42, {}, %w[u x] ] }) }
		end

		test "rejects the wrong kind" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce), kind: 1)

			assert_raises(AuthenticationError) { authenticate(event) }
		end

		test "rejects a stale timestamp" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce), created_at: 1.hour.ago.to_i)

			assert_raises(AuthenticationError) { authenticate(event) }
		end

		test "rejects a method mismatch" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce, http_method: "GET"))

			assert_raises(AuthenticationError) { authenticate(event, http_method: "POST") }
		end

		test "rejects a u-tag mismatch" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce, url: "https://evil.example/session"))

			assert_raises(AuthenticationError) { authenticate(event) }
		end

		test "rejects a tampered event whose signature no longer matches" do
			event = sign(tags: auth_tags(challenge: LoginChallenge.issue.nonce))
			event["content"] = "tampered"

			assert_raises(InvalidEventError) { authenticate(event) }
		end

		private

		def authenticate(event, http_method: "POST")
			Sessions::Authenticate.call(event_data: event, http_method:, url: verify_url)
		end

		def auth_tags(challenge:, url: nil, http_method: "POST")
			tags = [ [ "u", url || verify_url ], [ "method", http_method ] ]
			tags << [ "challenge", challenge ] if challenge
			tags
		end

		def sign(tags:, created_at: Time.now.to_i, kind: Events::Kinds::HTTP_AUTH, content: "")
			keypair = Nostr::Keygen.new.generate_key_pair
			pubkey = keypair.public_key.to_s
			id = Digest::SHA256.hexdigest(JSON.generate([ 0, pubkey, created_at, kind, tags, content ]))
			sig = Nostr::Crypto.new.sign_message(id, keypair.private_key).to_s
			{
				"id" => id, "pubkey" => pubkey, "created_at" => created_at, "kind" => kind,
				"tags" => tags, "content" => content, "sig" => sig
			}
		end

		def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
	end
end
