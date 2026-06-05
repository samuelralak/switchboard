# frozen_string_literal: true

require "test_helper"

# The opaque inbox: anonymous deposit (POST) + session-authenticated recipient-only fetch (GET).
class InboxControllerTest < ActionDispatch::IntegrationTest
	# --- deposit: anonymous, like a relay accepting an EVENT ---

	test "deposits an anonymous gift wrap" do
		recipient = fresh_pubkey

		post inbox_url, params: gift_wrap(recipient).to_json, headers: json_headers

		assert_response :created
		assert_equal recipient, InboxWrap.sole.recipient_pubkey
	end

	test "dedups a re-deposited wrap" do
		wrap = gift_wrap(fresh_pubkey)

		2.times { post inbox_url, params: wrap.to_json, headers: json_headers }

		assert_response :created
		assert_equal 1, InboxWrap.count
	end

	test "stores the deposited wrap byte-for-byte (canonical fields)" do
		wrap = gift_wrap(fresh_pubkey, content: "round-trip me")

		post inbox_url, params: wrap.to_json, headers: json_headers

		assert_response :created
		assert_equal wrap, InboxWrap.sole.wrap
	end

	test "rejects a non-gift-wrap event" do
		note = sign_event(kind: Events::Kinds::CLASSIFIED, tags: [ %w[d x] ], content: "hi")

		post inbox_url, params: note.to_json, headers: json_headers

		assert_response :unprocessable_content
		assert_equal 0, InboxWrap.count
	end

	test "rejects a malformed body" do
		post inbox_url, params: "not json", headers: json_headers

		assert_response :unprocessable_content
	end

	# An otherwise-VALID wrap that is merely too big: proves the size guard, not Verify, rejects it
	# (without the guard this deposit would verify and store).
	test "rejects an oversized but valid wrap before parsing" do
		big = gift_wrap(fresh_pubkey, content: "a" * (InboxController::MAX_WRAP_BYTES + 1))

		post inbox_url, params: big.to_json, headers: json_headers

		assert_response :unprocessable_content
		assert_equal 0, InboxWrap.count
	end

	# --- fetch: session-authenticated, recipient-only ---

	test "fetch requires a signed-in session" do
		get inbox_url

		assert_response :unauthorized
	end

	test "fetch returns only the signed-in recipient's wraps, with a cursor" do
		me = sign_in
		deposit(gift_wrap(me, content: "mine"))
		deposit(gift_wrap(fresh_pubkey, content: "theirs"))

		get inbox_url

		assert_response :success
		wraps = response.parsed_body["wraps"]
		assert_equal 1, wraps.size
		assert_equal me, wraps.first.dig("tags", 0, 1)
		assert response.parsed_body["cursor"].present?
	end

	test "fetch excludes wraps past their retention horizon" do
		me = sign_in
		deposit(gift_wrap(me, content: "live"))
		attrs = { recipient_pubkey: me, wrap_id: SecureRandom.hex(32), wrap: { "kind" => 1059 } }
		InboxWrap.create!(**attrs, nostr_created_at: Time.current, expires_at: 1.minute.ago)

		get inbox_url

		assert_equal 1, response.parsed_body["wraps"].size
	end

	test "fetch resumes from the cursor without re-returning consumed wraps" do
		me = sign_in
		deposit(gift_wrap(me, content: "one"))
		deposit(gift_wrap(me, content: "two"))

		get inbox_url
		first = response.parsed_body
		assert_equal 2, first["wraps"].size

		get inbox_url, params: { cursor: first["cursor"] }
		assert_response :success
		assert_empty response.parsed_body["wraps"]
	end

	private

	def json_headers = { "Content-Type" => "application/json" }

	def fresh_pubkey = Nostr::Keygen.new.generate_key_pair.public_key.to_s

	def gift_wrap(recipient, content: "cipher")
		sign_event(kind: Events::Kinds::GIFT_WRAP, tags: [ [ "p", recipient ] ], content:)
	end

	def deposit(wrap)
		post inbox_url, params: wrap.to_json, headers: json_headers
		assert_response :created
	end

	# Establishes a browser session via the NIP-98 sign-in flow; returns the signed-in pubkey.
	def sign_in
		keypair = Nostr::Keygen.new.generate_key_pair
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
		keypair.public_key.to_s
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
end
