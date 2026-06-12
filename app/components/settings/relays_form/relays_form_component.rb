# frozen_string_literal: true

module Settings
	module RelaysForm
		# The non-custodial relay-list (NIP-65) editor: edit your kind-10002 read/write relays, then sign +
		# broadcast the list in the browser (no server write). The rows prefill from the projected user_relays
		# (or the platform seeds for a user who has not advertised a list yet, so the form opens on a sensible
		# default rather than empty). The `relay-form` Stimulus controller hydrates the rows from a single
		# <template> and rebuilds the kind-10002 WHOLESALE on publish (a NIP-65 list is replaceable, so there is
		# nothing to merge, unlike the profile editor). Mirrors Settings::ProfileForm.
		class RelaysFormComponent < ApplicationComponent
			attr_reader :user, :pubkey, :publish_relays

			def initialize(user:, pubkey:, publish_relays:)
				@user = user
				@pubkey = pubkey
				@publish_relays = publish_relays
			end

			# The prefill rows the editor hydrates: the user's advertised NIP-65 relays (full url + read/write
			# roles), or the platform seeds (read + write) when they have not published a list yet.
			def relay_rows
				rows = user.user_relays.order(:url).pluck(:url, :read, :write)
				rows = seed_rows if rows.empty?

				rows.map { |url, read, write| { url:, read:, write: } }
			end

			private

			def seed_rows
				NostrClient.configuration.relays.map { |url| [ url, true, true ] }
			end
		end
	end
end
