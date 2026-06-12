# frozen_string_literal: true

require "application_system_test_case"

# Drives the real request-form Stimulus controller in headless Chrome: strict client validation, the
# section-rail progress, the funding coming-soon gate, and the on-demand preview. Signs in with a stubbed
# approving NIP-07 extension (same path as SignInTest) so the auth-gated composer loads.
class RequestFormTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
		sign_in
		visit new_request_path
		assert_text "Post an open request"
	end

	test "the funding panel states the fund-at-claim model, with only the posting fee marked coming soon" do
		assert_text "claims it, you lock the budget to them" # fund-at-claim, not fund-at-post
		assert_no_text "deposited into escrow up front" # the superseded reservation wording is gone
		assert_text "non-refundable posting fee"
		assert_text "COMING SOON" # the pill, now scoped to the fee (CSS-uppercased "Fee coming soon")
	end

	test "strict validation blocks an empty post and lists the problems" do
		fill_in "title", with: ""
		fill_in "capability", with: ""
		fill_in "budget", with: ""
		click_button "Sign & post request"

		assert_text "Add a title for your request."
		assert_text "Add a capability tag."
		assert_text "Set a budget in sats"
	end

	test "the progress dot fills once the budget section's required field is satisfied" do
		budget_dot = find('[data-request-form-target="navItem"][data-section="budget"] [data-role="dot"]')
		assert_not_includes budget_dot[:class], "bg-copper" # incomplete at first

		fill_in "budget", with: "5000"

		dot = find('[data-request-form-target="navItem"][data-section="budget"] [data-role="dot"]')
		assert_includes dot[:class], "bg-copper"
	end

	test "preview opens the drawer with the current form rendered as the board view" do
		fill_in "title", with: "Diagnose an engine"
		fill_in "capability", with: "diagnosis"
		fill_in "budget", with: "5000"

		click_button "Preview request"

		within "#request-preview" do
			assert_text "Diagnose an engine" # requests#preview rendered the real detail component into the drawer
		end
	end

	private

	def sign_in
		execute_script(<<~JS)
		  const backing = window.NostrCryptoTest.NsecSigner.generate()
		  window.nostr = { getPublicKey: () => backing.getPublicKey(), signEvent: (t) => backing.signEvent(t) }
		JS
		click_button "Sign in"
		click_button "Browser extension"
		assert_text "Provider studio" # the signed-in header CTA; also blocks until the post-auth reload lands
	end
end
