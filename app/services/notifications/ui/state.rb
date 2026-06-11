# frozen_string_literal: true

module Notifications
	module Ui
		# Render state for a recipient's notification bell, shared by the initial render and the live broadcast so
		# both use the same per-user stream, the same target ids, and the same row/badge partials. Mirrors
		# Orders::Ui::State on the notifications side.
		module State
			LIST_TARGET  = "notifications-list"
			BADGE_TARGET = "notifications-badge"
			PARTIAL      = "notifications/notification"
			BADGE        = "notifications/badge"

			# One per-user stream; every authed page subscribes via the bell component.
			def self.stream(pubkey) = "notifications:#{pubkey}"
		end
	end
end
