# frozen_string_literal: true

require "application_system_test_case"

# Proves the cross-cutting signer persistence (#68) for the riskiest tier, a pasted nsec: the decrypted
# key is held in the in-memory SignerRegistry, survives Turbo soft navigation to the studio (so an
# upload signs with NO browser extension and NO re-prompt), and after a HARD reload is re-hydrated
# through the unlock dialog (passphrase -> decrypt the saved NIP-49 key). Blossom uploads are stubbed.
class SignerPersistenceTest < ApplicationSystemTestCase
	STUB_URL = "https://stub.blossom.band/persist.png"
	PASSPHRASE = "correct horse battery staple"

	def setup
		keypair = Nostr::Keygen.new.generate_key_pair
		@pubkey = keypair.public_key.to_s
		@nsec = Nostr::Bech32.nsec_encode(keypair.private_key.to_s)
		visit root_path
		load_nostr_bridge
	end

	test "a pasted nsec stays usable across navigation to the studio, with no extension and no re-prompt" do
		sign_in_with_nsec

		click_link "Provider studio"                  # soft nav -> /studio
		click_link "Publish a service", match: :first # soft nav -> /studio/new; the held NsecSigner persists
		assert_text "No code runs on Switchboard"

		stub_uploads_only # NOTE: window.nostr is NEVER set here, so a working upload can only come from the registry
		attach_image

		assert_selector '[data-image-upload-target="item"][data-state="done"]', count: 1
		assert_equal STUB_URL, find('[data-field="url"]', visible: :all).value
	end

	test "after a hard reload an nsec user unlocks via the dialog to upload" do
		sign_in_with_nsec # saves the NIP-49 ciphertext on this device
		visit new_studio_listing_url # HARD reload: the in-memory registry is gone, the ciphertext + method persist
		assert_text "Publish a service"
		stub_uploads_only

		attach_image # addFile -> ensureSigner(prompt) -> needsUnlock -> opens the unlock dialog
		within "#signer-unlock-dialog" do
			assert_text expected_short_npub # the dialog names the account it is unlocking
			find('[data-signer-unlock-target="passphrase"]').set(PASSPHRASE)
			click_button "Unlock"
		end

		assert_selector '[data-image-upload-target="item"][data-state="done"]', count: 1
	end

	test "the saved key is pubkey-scoped: the legacy slot is retired and the account map is written" do
		sign_in_with_nsec

		assert_nil page.evaluate_script("window.localStorage.getItem('switchboard.nsec')"), "legacy single slot is retired"
		map = JSON.parse(page.evaluate_script("window.localStorage.getItem('switchboard.nsec.v2')") || "{}")
		assert_includes map.keys, @pubkey, "the ciphertext is stored under the account pubkey"
		assert_equal @pubkey, page.evaluate_script("window.localStorage.getItem('switchboard.nsec.last')")
	end

	private

	# The npub the dialog renders, truncated to the same 8…4 shape as the component.
	def expected_short_npub
		npub = Nostr::Bech32.npub_encode(@pubkey)
		"#{npub[0, 8]}…#{npub[-4..]}"
	end

	def sign_in_with_nsec
		click_button "Sign in"
		click_button "Private key" # the sign-in dialog tab
		find('[data-nostr-auth-target="nsec"]').set(@nsec)
		find('[data-nostr-auth-target="savePassphrase"]').set(PASSPHRASE)
		click_button "Sign in with key"
		assert_text "Provider studio" # signed in
	end

	def attach_image
		find('input[type="file"]', visible: :all).set(Rails.public_path.join("icon.png"))
	end

	def stub_uploads_only
		execute_script(<<~JS)
		  const real = window.fetch.bind(window)
		  window.fetch = (url, opts) => String(url).includes("/upload")
		    ? Promise.resolve(new Response(JSON.stringify({ url: "#{STUB_URL}", sha256: "d", size: 1, type: "image/png" }), { status: 201, headers: { "Content-Type": "application/json" } }))
		    : real(url, opts)
		JS
	end
end
