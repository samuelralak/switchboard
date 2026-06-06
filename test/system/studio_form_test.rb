# frozen_string_literal: true

require "application_system_test_case"

# Drives the real studio Stimulus controller in headless Chrome: the schema-row repeater, the
# fulfillment mode, strict client validation, and the on-demand buyer preview. Signs in with a stubbed
# approving NIP-07 extension (same path as SignInTest) so the auth-gated studio loads.
class StudioFormTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
		sign_in
		visit new_studio_listing_path
		assert_text "Publish a service"
	end

	test "adds and removes input-schema rows" do
		assert_no_selector '[data-studio-target="row"]'

		click_button "Add field"
		click_button "Add field"
		assert_selector '[data-studio-target="row"]', count: 2

		within first('[data-studio-target="row"]') do
			find('button[aria-label="Remove field"]').click
		end
		assert_selector '[data-studio-target="row"]', count: 1
	end

	test "auto-slugs the machine name from the label and lets the provider override it" do
		click_button "Add field"
		row = first('[data-studio-target="row"]')

		row.find('[data-studio-target="rowLabel"]').set("Source Text!")
		assert_equal "source_text", row.find('[data-studio-target="rowName"]').value

		name = row.find('[data-studio-target="rowName"]')
		name.set("custom_key")
		row.find('[data-studio-target="rowLabel"]').set("A Different Label")
		assert_equal "custom_key", name.value # manual edit wins over the auto-slug
	end

	test "manual is the default fulfillment mode and automated is shown as coming soon" do
		assert_selector '[data-studio-target="modeManual"]', visible: true # the delivery-window fields
		assert_text "COMING SOON" # the automated card is disabled until it ships (CSS-uppercased pill)
		assert_equal "manual", find('[data-studio-target="modeInput"]', visible: false).value
	end

	test "strict validation blocks an empty publish and lists the problems" do
		click_button "Sign & publish listing"

		assert_text "Add a service name."
		assert_text "Add a capability tag."
		assert_text "Set a price in sats"
	end

	test "the progress dot fills once the details section's required fields are satisfied" do
		details_dot = find('[data-studio-target="navItem"][data-section="details"] [data-role="dot"]')
		assert_not_includes details_dot[:class], "bg-copper" # incomplete at first

		fill_in "title", with: "Translate a document"
		fill_in "capability", with: "translate"
		fill_in "price", with: "120"

		dot = find('[data-studio-target="navItem"][data-section="details"] [data-role="dot"]')
		assert_includes dot[:class], "bg-copper"
	end

	test "the per-hour pricing basis relabels the price unit and sets the NIP-99 frequency" do
		assert_equal "", find('[data-studio-target="priceFrequency"]', visible: false).value # per request

		click_button "Per hour"
		assert_equal "hour", find('[data-studio-target="priceFrequency"]', visible: false).value
		assert_equal "(SAT / HR)", find('[data-studio-target="priceUnit"]').text # CSS-uppercased label

		click_button "Per request"
		assert_equal "", find('[data-studio-target="priceFrequency"]', visible: false).value
		assert_equal "(SAT)", find('[data-studio-target="priceUnit"]').text
	end

	test "preview as buyer opens the drawer with the current form rendered as the buyer view" do
		fill_in "title", with: "Translate a document"
		fill_in "capability", with: "translate"
		fill_in "price", with: "120"

		click_button "Preview as buyer"

		within "#studio-preview" do
			assert_text "Translate a document" # studio#preview rendered the real buyer component into the drawer
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
