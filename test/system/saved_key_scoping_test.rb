# frozen_string_literal: true

require "application_system_test_case"

# The pubkey-scoped saved-key map (#69 T3.14): a second account's saved key must not clobber the first,
# the pre-sign-in dialog offers the most recently saved one, and the legacy single slot is retired once a
# scoped key exists. Drives the store's storage helpers directly through the test bridge (deterministic,
# no UI), the repo's pattern for unit-testing the keyless JS.
class SavedKeyScopingTest < ApplicationSystemTestCase
	def setup
		visit root_path
		load_nostr_bridge
	end

	test "a second account's key does not clobber the first; the most recent is offered; legacy is retired" do
		result = evaluate_async_script(<<~JS)
		  const done = arguments[arguments.length - 1]
		  const { saveNsec, nsecFor, savedNsecEntry } = window.NostrCryptoTest
		  localStorage.clear()
		  localStorage.setItem("switchboard.nsec", "legacyCipher") // a pre-migration single-slot key
		  const A = "aa".repeat(32), B = "bb".repeat(32)
		  saveNsec(A, "cipherA")
		  saveNsec(B, "cipherB")
		  done(JSON.stringify({
		    a: nsecFor(A), b: nsecFor(B), other: nsecFor("cc".repeat(32)),
		    recent: savedNsecEntry(), legacy: localStorage.getItem("switchboard.nsec"),
		  }))
		JS
		data = JSON.parse(result)

		assert_equal "cipherA", data["a"], "account A's key survives B's save"
		assert_equal "cipherB", data["b"], "account B's key is stored under its own pubkey"
		assert_nil data["other"], "a third account with no saved key is not offered another account's key"
		assert_equal "bb" * 32, data.dig("recent", "pubkey"), "the most recently saved key is offered pre-sign-in"
		assert_nil data["legacy"], "the legacy single slot is retired once scoped keys exist"
	end
end
