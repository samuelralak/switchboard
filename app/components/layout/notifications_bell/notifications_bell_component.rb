# frozen_string_literal: true

module Layout
	module NotificationsBell
		# The top-bar notifications bell: an unseen-count badge + an el-dropdown listing the recipient's recent
		# notifications, subscribed to the per-user Turbo Stream so new ones arrive live. Opening the dropdown
		# marks everything seen (clearing the badge) via the `notifications` Stimulus controller.
		class NotificationsBellComponent < ApplicationComponent
			LIMIT = 12

			def initialize(user:)
				@user = user
			end

			def notifications
				@notifications ||= Notification.for_recipient(@user.pubkey).recent.limit(LIMIT)
			end

			def unseen_count
				@unseen_count ||= Notification.for_recipient(@user.pubkey).unseen.count
			end

			def stream = Notifications::Ui::State.stream(@user.pubkey)
			def list_target = Notifications::Ui::State::LIST_TARGET
		end
	end
end
