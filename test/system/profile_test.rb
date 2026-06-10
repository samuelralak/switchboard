# frozen_string_literal: true

require "application_system_test_case"

# Verifies the non-custodial profile editor: the form prefills, and "Sign & publish profile" signs a kind-0
# with the held nsec key and broadcasts it to the relays, surfacing a success receipt. Covers the
# browser sign+broadcast path; the wire shape + merge-onto-base are unit-covered (profile_publish.js /
# ProfileFormComponent). The avatar upload reuses the Blossom flow exercised by StudioImagesTest.
class ProfileTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@pubkey = keypair.public_key.to_s
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "editing a profile signs and broadcasts a kind-0, then reports the relays reached" do
		sign_in_with_nsec
		# Turbo soft-navigation (not a hard visit) so the in-memory nsec signer + the test relay bridge survive.
		# /settings redirects to the profile editor (the default settings section).
		click_link "Settings"

		assert_button "Sign & publish profile"
		find("[data-field='display_name']").set("Ada Lovelace")
		find("[data-field='about']").set("I count things.")

		install_mock_relays
		click_button "Sign & publish profile"

		assert_selector "[data-profile-form-target='status']", text: "Published to", visible: true
		assert_no_text "Couldn't"
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
		assert_no_button "Sign in" # the identity menu replaces the sign-in button once authed
	end
end
