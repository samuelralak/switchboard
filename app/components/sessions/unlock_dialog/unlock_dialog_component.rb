# frozen_string_literal: true

module Sessions
	module UnlockDialog
		# A passphrase dialog for re-hydrating a saved nsec signer after a hard reload (the in-memory
		# SignerRegistry does not survive one). Rendered in the layout when signed in, and opened
		# programmatically by signer_unlock_controller when the store requests an unlock. It shows which
		# account it is unlocking (npub + profile) and the controller decrypts the ciphertext saved for
		# that pubkey. The decrypted key is held in tab memory only; the server never sees it.
		class UnlockDialogComponent < ApplicationComponent
			include IdenticonHelper

			DIALOG_ID = "signer-unlock-dialog"

			def initialize(user:)
				@user = user
			end

			delegate :pubkey, to: :@user

			def picture = @user.picture.presence
			def display_label = @user.display_name.presence || @user.name.presence || display_npub

			# The account npub, truncated to a prefix and suffix (same shape as the identity menu).
			def display_npub
				npub = @user.npub
				npub.length <= 14 ? npub : "#{npub[0, 8]}…#{npub[-4..]}"
			end
		end
	end
end
