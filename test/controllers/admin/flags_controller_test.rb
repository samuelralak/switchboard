# frozen_string_literal: true

require "test_helper"

module Admin
	class FlagsControllerTest < ActionDispatch::IntegrationTest
		teardown { Rails.application.config.x.operator_pubkeys = @saved_operators if defined?(@saved_operators) }

		test "redirects a logged-out visitor home" do
			get admin_flags_url

			assert_redirected_to root_path
		end

		test "redirects a signed-in non-operator home" do
			sign_in # a random pubkey, not on the allowlist

			get admin_flags_url

			assert_redirected_to root_path
		end

		test "an operator flags a pubkey by hex" do
			sign_in_as_operator
			pubkey = SecureRandom.hex(32)

			post admin_flags_url, params: { pubkey: }

			assert_redirected_to admin_flags_path
			assert User.find_by(pubkey:)&.flagged?
		end

		test "an operator flags a pubkey given as an npub" do
			sign_in_as_operator
			pubkey = SecureRandom.hex(32)

			post admin_flags_url, params: { pubkey: Nostr::Bech32.npub_encode(pubkey) }

			assert User.find_by(pubkey:)&.flagged?
		end

		test "an operator unflags a pubkey" do
			sign_in_as_operator
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, flagged: true)

			delete admin_flag_url(user.pubkey)

			assert_redirected_to admin_flags_path
			assert_not user.reload.flagged?
		end

		test "rejects an invalid pubkey without flagging anything" do
			sign_in_as_operator

			post admin_flags_url, params: { pubkey: "garbage" }

			assert_redirected_to admin_flags_path
			assert_equal 0, User.where(flagged: true).count
		end

		test "flagging an existing identity preserves its profile projection" do
			sign_in_as_operator
			user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, name: "alice")

			post admin_flags_url, params: { pubkey: user.pubkey }

			assert user.reload.flagged?
			assert_equal "alice", user.name # the flag must not clobber the kind-0 projection
		end

		private

		def sign_in_as_operator
			sign_in
			@saved_operators = Rails.application.config.x.operator_pubkeys
			Rails.application.config.x.operator_pubkeys = [ @session_pubkey ]
		end

		def sign_in
			keypair = Nostr::Keygen.new.generate_key_pair
			@session_pubkey = keypair.public_key.to_s
			tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
			event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
			post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
			assert_response :created
		end

		def verify_url
			"#{Rails.application.config.x.canonical_origin}/session"
		end
	end
end
