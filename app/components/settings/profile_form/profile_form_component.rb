# frozen_string_literal: true

module Settings
	module ProfileForm
		# The non-custodial profile editor: edit your kind-0 metadata, then sign + broadcast it in the browser
		# (no server write). Text fields prefill from the projected User columns; the avatar/banner reuse the
		# Blossom upload. The raw winning kind-0 (content + tags) rides along as a merge base so the publish
		# OVERLAYS the edited fields onto it -- preserving NIP-39 identities and any fields this form does not
		# manage -- rather than replacing the replaceable event wholesale. The `profile-form` Stimulus controller
		# collects fields by their data-field key (not input name), so simple_form's nesting is irrelevant.
		class ProfileFormComponent < ApplicationComponent
			include Forms::Fields # LABEL/input_class for the bespoke image rows

			attr_reader :user, :pubkey, :publish_relays, :metadata_event

			def initialize(user:, pubkey:, publish_relays:, metadata_event: nil)
				@user = user
				@pubkey = pubkey
				@publish_relays = publish_relays
				@metadata_event = metadata_event
			end

			# The raw winning kind-0 the browser merges onto: its content JSON + tags, or empty for a first profile.
			def base_event
				{ content: metadata_event&.content.presence || "{}", tags: metadata_event&.tags || [] }
			end
		end
	end
end
