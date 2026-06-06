# frozen_string_literal: true

require "application_system_test_case"

# Drives the studio image picker in headless Chrome with the Blossom network stubbed (window.fetch for
# /upload) and a stub NIP-07 signer, so it tests the picker pipeline deterministically: file -> data:
# preview -> kind-24242-authorized upload -> hidden imeta inputs -> image-upload:changed -> the live
# buyer preview renders the cover. The REAL blossom.band round-trip is proven separately by the probe.
class StudioImagesTest < ApplicationSystemTestCase
	STUB_URL = "https://stub.blossom.band/deadbeefcafe.png"

	def setup
		visit root_path
		load_nostr_bridge
		sign_in
		visit new_studio_listing_path
		assert_text "Publish a service"
		stub_browser_uploads
	end

	test "uploading an image adds a cover thumbnail and fills the imeta inputs" do
		attach_image

		assert_selector '[data-image-upload-target="item"][data-state="done"]', count: 1
		assert_equal STUB_URL, find('[data-field="url"]', visible: :all).value
		assert_equal "image/png", find('[data-field="m"]', visible: :all).value
		assert_selector '[data-role="cover"]', visible: true
	end

	test "removing an image clears it from the picker" do
		attach_image
		item = find('[data-image-upload-target="item"]')

		item.hover
		item.find('button[aria-label="Remove image"]').click

		assert_no_selector '[data-image-upload-target="item"]'
	end

	test "the 5-image cap holds even when more are selected at once" do
		find('input[type="file"]', visible: :all).set([ Rails.public_path.join("icon.png") ] * 6)

		assert_selector '[data-image-upload-target="item"]', count: 5
		assert_text "You can add up to 5 images."
	end

	test "a failed upload offers Retry that re-attempts the same file" do
		stub_browser_uploads_failing_once
		attach_image

		assert_selector '[data-image-upload-target="item"][data-state="error"]', count: 1
		assert_selector '[data-action~="image-upload#retry"]', visible: true

		find('[data-action~="image-upload#retry"]').click

		assert_selector '[data-image-upload-target="item"][data-state="done"]', count: 1
		assert_equal STUB_URL, find('[data-field="url"]', visible: :all).value
	end

	test "a signer whose key differs from the signed-in account is refused" do
		execute_script(%(window.nostr = { getPublicKey: async () => "11".repeat(32), signEvent: async (t) => t }))
		attach_image

		assert_text "different key than the account"
		assert_no_selector '[data-image-upload-target="item"]'
	end

	private

	def attach_image
		find('input[type="file"]', visible: :all).set(Rails.public_path.join("icon.png"))
	end

	# Fake the signer + the Blossom upload on the studio page; pass every other request (the Rails
	# preview POST) through to the real fetch. The stub signer returns the SAME pubkey that signed in, so
	# the studio's identity gate (ensureSignerFor) accepts it.
	def stub_browser_uploads
		execute_script(<<~JS)
		  window.nostr = { getPublicKey: async () => "#{@session_pubkey}", signEvent: async (t) => ({ ...t, id: "id", pubkey: "#{@session_pubkey}", sig: "00".repeat(64) }) }
		  const real = window.fetch.bind(window)
		  window.fetch = (url, opts) => String(url).includes("/upload")
		    ? Promise.resolve(new Response(JSON.stringify({ url: "#{STUB_URL}", sha256: "deadbeefcafe", size: 42, type: "image/png" }), { status: 201, headers: { "Content-Type": "application/json" } }))
		    : real(url, opts)
		JS
	end

	# Same as stub_browser_uploads but the first /upload fails (HTTP 500) and later ones succeed, so a
	# test can drive the error state and then a successful Retry.
	def stub_browser_uploads_failing_once
		execute_script(<<~JS)
		  window.nostr = { getPublicKey: async () => "#{@session_pubkey}", signEvent: async (t) => ({ ...t, id: "id", pubkey: "#{@session_pubkey}", sig: "00".repeat(64) }) }
		  const real = window.fetch.bind(window)
		  let attempts = 0
		  window.fetch = (url, opts) => {
		    if (!String(url).includes("/upload")) return real(url, opts)
		    attempts += 1
		    if (attempts === 1) return Promise.resolve(new Response("nope", { status: 500 }))
		    return Promise.resolve(new Response(JSON.stringify({ url: "#{STUB_URL}", sha256: "deadbeefcafe", size: 42, type: "image/png" }), { status: 201, headers: { "Content-Type": "application/json" } }))
		  }
		JS
	end

	def sign_in
		execute_script(<<~JS)
		  const backing = window.NostrCryptoTest.NsecSigner.generate()
		  window.nostr = { getPublicKey: () => backing.getPublicKey(), signEvent: (t) => backing.signEvent(t) }
		JS
		@session_pubkey = page.evaluate_script("window.nostr.getPublicKey()") # the account the gate expects
		click_button "Sign in"
		click_button "Browser extension"
		assert_text "Provider studio"
	end
end
