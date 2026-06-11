# frozen_string_literal: true

module Notifications
	module Ui
		# Pushes a freshly-recorded notification to the recipient's open bell: prepend the row to the dropdown
		# list and replace the unseen badge with the recomputed count. Triggered from Notifications::Deliver
		# (best-effort there), mirroring Orders::Ui::Update. A target absent on the open page is a harmless no-op.
		class Update
			def self.call(notification:)
				pubkey = notification.recipient_pubkey
				Turbo::StreamsChannel.broadcast_prepend_to(
					State.stream(pubkey), target: State::LIST_TARGET, partial: State::PARTIAL, locals: { notification: }
				)
				refresh_badge(pubkey:)
			end

			# Re-broadcast just the unseen badge to the recipient's stream (after a new notification or a bulk
			# mark-seen) so every open tab/device reflects the server's count, not just the one that acted.
			def self.refresh_badge(pubkey:)
				Turbo::StreamsChannel.broadcast_replace_to(
					State.stream(pubkey), target: State::BADGE_TARGET, partial: State::BADGE,
					locals: { count: Notification.for_recipient(pubkey).unseen.count }
				)
			end

			# Replace a single notification's own row on the recipient's open bells (e.g. after it is marked read,
			# so its unread dot clears across tabs/devices). The target matches the row partial's wrapper id.
			def self.refresh_row(notification:)
				Turbo::StreamsChannel.broadcast_replace_to(
					State.stream(notification.recipient_pubkey),
					target: "notification_#{notification.id}", partial: State::PARTIAL, locals: { notification: }
				)
			end
		end
	end
end
