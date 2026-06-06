# frozen_string_literal: true

module Settings
	module RelaysDialog
		# The manage-relays modal, opened with command="show-modal" commandfor=DIALOG_ID from the sidebar
		# relays group and the settings page. A UI shell for now: it lists the relays with add/remove
		# affordances but does not yet publish a NIP-65 / kind-10050 relay list.
		class RelaysDialogComponent < ApplicationComponent
			include RelaysHelper

			DIALOG_ID = "relays-dialog"
		end
	end
end
