# frozen_string_literal: true

require "application_system_test_case"

# Proves the NIP-07 sign-in path end to end with a stubbed APPROVING extension: open the dialog (which
# prefetches the challenge nonce), click "Browser extension", and the signed kind-27235 event must
# establish the Rails session. A real extension returning {error:"denied"} (rejected, or a remembered
# reject that shows no popup) is an extension-side decision, not a Switchboard failure; this test
# isolates the app's half so the two can't be confused.
class SignInTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "signing in with an approving NIP-07 extension establishes a session" do
		execute_script(<<~JS)
		  const backing = window.NostrCryptoTest.NsecSigner.generate()
		  window.nostr = { getPublicKey: () => backing.getPublicKey(), signEvent: (t) => backing.signEvent(t) }
		JS

		click_button "Sign in"           # opens the dialog + prefetches the challenge nonce (prepare)
		click_button "Browser extension" # signInWithExtension -> window.nostr.signEvent -> POST /session

		assert_text "signed in"          # the identity menu reflects the established session after reload
	end
end
