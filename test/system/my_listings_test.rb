# frozen_string_literal: true

require "application_system_test_case"

# Verifies My-listings management, now on the owner's profile (#66): the provider's listing renders, and Unpublish /
# Re-publish re-sign the existing event with the status tag flipped and flip the card IN PLACE (badge +
# button + success note). Signs with the held nsec key (identity-gated against the session pubkey). This
# covers the in-place UI flip only; the re-signed wire status is verified by ListingPublishTest.
class MyListingsTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@pubkey = keypair.public_key.to_s
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey: @pubkey, sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: "Logo design",
			tags: [ %w[d logo], [ "title", "Logo design" ], [ "t", Catalog::Listing.marker ], %w[price 120 sat] ],
			nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
		)
		visit root_path
		load_nostr_bridge
	end

	test "unpublishing a listing flips it to inactive in place, and re-publishing flips it back" do
		sign_in_with_nsec
		# Managing listings now lives on the owner's profile (the portfolio surface). Reach it through the
		# identity menu: a Turbo soft-nav that preserves the in-memory nsec signer (a hard visit would drop it
		# and force an unlock prompt mid-test).
		click_button "Open user menu"
		click_link "Your profile"

		assert_text "Logo design"
		# the badge is CSS-uppercased and Capybara reads rendered text; "ACTIVE" is a substring of
		# "INACTIVE", so match exactly.
		assert_selector '[data-role="status"]', text: "ACTIVE", exact_text: true

		install_mock_relays
		click_button "Unpublish"

		assert_selector '[data-role="status"]', text: "INACTIVE", exact_text: true
		assert_button "Re-publish"
		# Honest propagation note on success; the error slot stays hidden (mutually exclusive).
		assert_selector "[data-my-listings-card-note]", visible: true, text: "The public catalog may take a moment"
		assert_no_selector "[data-my-listings-card-error]", visible: true

		click_button "Re-publish"
		assert_selector '[data-role="status"]', text: "ACTIVE", exact_text: true
		assert_button "Unpublish"
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
		assert_text "Provider studio"
	end
end
