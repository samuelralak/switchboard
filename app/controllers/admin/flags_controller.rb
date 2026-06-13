# frozen_string_literal: true

module Admin
	# Operator takedown: flag/unflag a pubkey so the public surfaces (catalog, request board, profile page)
	# stop serving its content. `flagged` is operator state on the User projection, preserved across
	# re-projection, so flagging a pubkey we hold no kind-0 for still works -- we create the identity shell
	# to carry the flag. Reversible, and it never touches funds or escrow.
	class FlagsController < BaseController
		def index
			@flagged = User.where(flagged: true).order(updated_at: :desc)
		end

		def create
			pubkey = normalize(params.expect(:pubkey))
			return redirect_to(admin_flags_path, alert: "Not a valid npub or hex pubkey.") unless pubkey

			user = User.find_or_create_by!(pubkey:)
			user.update!(flagged: true)

			redirect_to admin_flags_path, notice: "Flagged #{user.npub}. Its listings, requests, and profile are now hidden."
		end

		def destroy
			User.find_by(pubkey: params.expect(:pubkey))&.update!(flagged: false)

			redirect_to admin_flags_path, notice: "Unflagged."
		end

		private

		# Accept either an npub (decoded to hex) or a raw 64-hex pubkey; nil when neither.
		def normalize(input)
			value = input.to_s.strip

			Events::Kinds::HEX64.match?(value) ? value : User.pubkey_from_npub(value)
		end
	end
end
