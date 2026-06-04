# frozen_string_literal: true

require "application_system_test_case"

# Verifies the JS test vehicle: the app boots, headless Chrome drives it, and a pinned module
# resolves + loads from the CDN under the app's CSP. If this passes, the crypto vector tests can
# rely on the same path. (A bare-specifier dynamic import from an executeScript-eval'd context does
# NOT consult the page import map, so we resolve the URL from the <script type="importmap"> first.)
class JavascriptVehicleTest < ApplicationSystemTestCase
	test "the app renders in headless chrome" do
		visit root_path
		assert_selector "h1", text: "What do you need done?"
	end

	test "a pinned module loads from the CDN under CSP" do
		visit root_path
		exported = evaluate_async_script(<<~JS)
    const done = arguments[arguments.length - 1]
    const imports = JSON.parse(document.querySelector('script[type="importmap"]').textContent).imports
    import(imports["nostr-tools/pure"])
    	.then((m) => done(typeof m.getPublicKey))
    	.catch((e) => done("ERR: " + (e && e.message)))
		JS
		assert_equal "function", exported
	end
end
