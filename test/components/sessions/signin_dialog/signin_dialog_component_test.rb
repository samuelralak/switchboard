# frozen_string_literal: true

require "test_helper"

module Sessions
	module SigninDialog
		class SigninDialogComponentTest < ViewComponent::TestCase
			def test_renders_the_three_sign_in_methods_as_tabs
				render_inline(SigninDialogComponent.new)

				assert_selector "dialog##{SigninDialogComponent::DIALOG_ID}"
				assert_selector "[role='tablist'][aria-label] [role='tab'][aria-controls]", count: 3
				assert_selector "[role='tabpanel'][aria-labelledby][id]", count: 3, visible: :all
				# Tab and panel cross-reference each other by index (WAI-ARIA association).
				assert_selector "[role='tab']#signin-tab-0[aria-controls='signin-panel-0']"
				assert_selector "[role='tabpanel']#signin-panel-0[aria-labelledby='signin-tab-0']", visible: :all
				# Roving tabindex: only the active tab is in the tab order.
				assert_selector "[role='tab'][tabindex='0']", count: 1
				assert_selector "[role='tab'][tabindex='-1']", count: 2
				assert_text "Browser extension"
				assert_text "Connect remote signer"
				assert_text "Sign in with key"
			end

			def test_private_key_tab_offers_paste_and_saved_key_unlock
				render_inline(SigninDialogComponent.new)

				# Paste-and-optionally-save (default).
				assert_selector "[data-nostr-auth-target='nsec']"
				assert_selector "[data-nostr-auth-target='savePassphrase']"
				assert_text "Least private"
				# Unlock a saved NIP-49 key (revealed by JS when one exists).
				assert_selector "[data-nostr-auth-target='unlockPassphrase']", visible: :all
				assert_selector "button", text: "Forget saved key", visible: :all
			end

			def test_wires_signer_targets_and_reassurance
				render_inline(SigninDialogComponent.new)

				assert_selector "[data-nostr-auth-target='extensionButton']"
				assert_selector "[data-nostr-auth-target='bunkerUrl']"
				assert_text "only ever receive the signed event"
			end
		end
	end
end
