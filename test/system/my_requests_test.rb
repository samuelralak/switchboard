# frozen_string_literal: true

require "application_system_test_case"

# Verifies My-requests management (#129, the demand-side mirror of the studio's #66): the poster's request
# renders, and Withdraw / Re-post re-sign the existing event with the status tag flipped and flip the card
# IN PLACE (badge + button + success note). Signs with the held nsec key (identity-gated against the
# session pubkey). Covers the in-place UI flip only; the re-signed wire path is the same one
# RequestPublishTest exercises for publishing.
class MyRequestsTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@pubkey = keypair.public_key.to_s
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey: @pubkey, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: "Diagnose a stalling engine from a video",
			tags: [ %w[d need], [ "title", "Diagnose an engine" ], [ "t", Requests::OpenRequest.marker ],
							%w[price 5000 sat], %w[claim_window 3d] ],
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
		visit root_path
		load_nostr_bridge
	end

	test "withdrawing a request flips it to withdrawn in place, and re-posting flips it back" do
		sign_in_with_nsec
		click_link "My requests"

		assert_text "Diagnose an engine"
		assert_selector '[data-role="status"]', text: "OPEN", exact_text: true

		install_mock_relays
		click_button "Withdraw"

		assert_selector '[data-role="status"]', text: "WITHDRAWN", exact_text: true
		assert_button "Re-post"
		# Honest propagation note on success; the error slot stays hidden (mutually exclusive).
		assert_selector "[data-my-requests-card-note]", visible: true, text: "The public board may take a moment"
		assert_no_selector "[data-my-requests-card-error]", visible: true

		click_button "Re-post"
		assert_selector '[data-role="status"]', text: "OPEN", exact_text: true
		assert_button "Withdraw"
	end

	private

	def install_mock_relays
		execute_script(<<~JS)
		  window.NostrCryptoTest.installMockRelays([
		    { url: "wss://relay.damus.io" }, { url: "wss://relay.nostr.band" }, { url: "wss://nos.lol" }
		  ])
		JS
	end

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_link "My requests"
	end
end
