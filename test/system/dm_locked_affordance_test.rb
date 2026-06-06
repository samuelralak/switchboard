# frozen_string_literal: true

require "application_system_test_case"

# The messages page must not auto-pop the unlock dialog on a passive load (#69 T3.15): a locked nsec
# session shows a quiet inline affordance, and only a click (a real user gesture) opens the unlock dialog.
class DmLockedAffordanceTest < ApplicationSystemTestCase
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "opening messages while locked shows a quiet affordance and does not auto-open unlock" do
		sign_in_with_nsec # saves the NIP-49 ciphertext + sets method=nsec
		visit direct_messages_url # HARD reload: the in-memory signer is gone, the ciphertext + method persist

		assert_selector "[data-dm-client-target='locked']", visible: true
		assert_text "Unlock to load your messages"
		assert_no_selector "#signer-unlock-dialog", visible: true # the modal did NOT auto-open

		click_button "Unlock" # a real user gesture
		assert_selector "#signer-unlock-dialog", visible: true # now the passphrase dialog opens
	end

	private

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key"
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_text "Provider studio"
	end
end
