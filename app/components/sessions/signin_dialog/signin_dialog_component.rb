# frozen_string_literal: true

module Sessions
	module SigninDialog
		# The sign-in modal (Tailwind Elements el-dialog), opened instantly by the identity
		# menu's "Sign in" button via the native command invoker. Offers NIP-07 (browser
		# extension) and NIP-46 (remote signer / bunker). It renders inside the identity
		# menu's nostr-auth Stimulus controller, which performs the signing.
		class SigninDialogComponent < ApplicationComponent
			DIALOG_ID = "signin-dialog"
		end
	end
end
