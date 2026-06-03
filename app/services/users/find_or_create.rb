# frozen_string_literal: true

module Users
	# Ensures a bare User row exists for a pubkey (no profile yet; Users::Upsert fills it
	# when the kind-0 arrives). Used at sign-in, where the pubkey is already verified.
	class FindOrCreate < BaseService
		option :pubkey, type: Types::Strict::String

		def call = User.find_or_create_by!(pubkey:)
	end
end
