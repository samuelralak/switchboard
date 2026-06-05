# frozen_string_literal: true

require "test_helper"

# Real-world end-to-end: a GENUINE NIP-59 gift wrap (built by the real crypto spine, not a stub event)
# survives anonymous HTTP deposit -> session-authed fetch -> unwrap back to the original rumor. Proves
# the cache stores decryptable, byte-faithful real wraps and isolates recipients under real sessions.
class InboxRealCryptoTest < ActionDispatch::IntegrationTest
	def setup
		@sender = Nostr::Keygen.new.generate_key_pair
		@recipient = Nostr::Keygen.new.generate_key_pair
	end

	test "a real gift wrap round-trips deposit -> fetch -> unwrap to the original rumor" do
		wrap = real_wrap_for(@recipient, "ping over the real path")

		post inbox_url, params: wrap.to_json, headers: json_headers # anonymous deposit, no session
		assert_response :created

		sign_in_as(@recipient)
		get inbox_url
		assert_response :success

		fetched = response.parsed_body["wraps"].sole
		assert_equal wrap, fetched # byte-faithful through jsonb + canonical slice
		assert_equal "ping over the real path", unwrap(fetched, @recipient)["content"]
	end

	test "a recipient never receives another recipient's real wrap" do
		deposit(real_wrap_for(Nostr::Keygen.new.generate_key_pair, "not for me"))
		deposit(real_wrap_for(@recipient, "for me"))

		sign_in_as(@recipient)
		get inbox_url

		fetched = response.parsed_body["wraps"].sole
		assert_equal "for me", unwrap(fetched, @recipient)["content"]
	end

	test "canonical-field slicing on deposit does not corrupt a real wrap's decryptability" do
		wrap = real_wrap_for(@recipient, "extra keys dropped").merge("ots" => "x", "garbage" => [ 1, 2 ])
		deposit(wrap)

		sign_in_as(@recipient)
		get inbox_url

		fetched = response.parsed_body["wraps"].sole
		assert_equal %w[content created_at id kind pubkey sig tags], fetched.keys.sort
		assert_equal "extra keys dropped", unwrap(fetched, @recipient)["content"]
	end

	private

	def json_headers = { "Content-Type" => "application/json" }
	def pub(keypair) = keypair.public_key.to_s
	def priv(keypair) = keypair.private_key.to_s

	def real_wrap_for(recipient, content)
		rumor = Messages::BuildRumor.call(author_pubkey: pub(@sender), content:, recipients: [ pub(recipient) ])
		seal = Messages::Seal.call(rumor:, author_private_key: priv(@sender), recipient_pubkey: pub(recipient))
		Messages::GiftWrap.call(seal:, recipient_pubkey: pub(recipient))
	end

	def unwrap(wrap, recipient)
		Messages::Unwrap.call(gift_wrap: wrap, recipient_private_key: priv(recipient))
	end

	def deposit(wrap)
		post inbox_url, params: wrap.to_json, headers: json_headers
		assert_response :created
	end

	def sign_in_as(keypair)
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
