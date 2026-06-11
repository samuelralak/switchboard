# frozen_string_literal: true

module Notifications
	# Records one recipient-addressed notification (a read-model projection of a server-observable event).
	# Callers fire this from an after_commit alongside the domain write, so it is a pure observer and never
	# mutates domain state. The live broadcast to the recipient's stream lands with the bell UI (a later slice);
	# this slice persists the row, which the bell renders on load.
	class Deliver < BaseService
		option :recipient_pubkey, type: Types::Strict::String
		option :notification_type, type: Types::Strict::String
		option :metadata, type: Types::Strict::Hash, default: -> { {} }

		def call
			notification = Notification.create!(recipient_pubkey:, notification_type:, metadata:)
			broadcast(notification)
			notification
		end

		private

		# Live push to the recipient's bell. Best-effort: a broadcast failure must not fail the recorded row
		# (it still appears on the next page load).
		def broadcast(notification)
			Notifications::Ui::Update.call(notification:)
		rescue StandardError => e
			Rails.error.report(e, handled: true, context: { notification_id: notification.id })
		end
	end
end
